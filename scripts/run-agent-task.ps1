[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Task)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$rootResolvedPath = (Resolve-Path -LiteralPath $root).Path
$reportDir = Join-Path $root 'reports/agent-task'
$summaryPath = Join-Path $reportDir 'summary.json'
$model = 'gpt-5.6-luna'
$allowedTestScopes = @('BslOnly', 'EpfBuildOnly')
$maxRepairAttempts = 2
$codexExecutablePath = ''
$codexExecutableKind = ''
$agentRuns = @()
$testHistory = @()
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function ConvertTo-ProcessArgument { param([AllowNull()][string]$Argument)
    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $b = New-Object System.Text.StringBuilder; [void]$b.Append([char]34); $slashes = 0
    foreach ($c in $Argument.ToCharArray()) {
        if ($c -eq [char]92) { $slashes++; continue }
        if ($c -eq [char]34) { if ($slashes -gt 0) { [void]$b.Append([char]92, (2*$slashes+1)) }; [void]$b.Append([char]34); $slashes=0; continue }
        if ($slashes -gt 0) { [void]$b.Append([char]92, $slashes) }; [void]$b.Append($c); $slashes=0
    }
    if ($slashes -gt 0) { [void]$b.Append([char]92, (2*$slashes)) }; [void]$b.Append([char]34); $b.ToString()
}
function Invoke-NativeProcess {
    param([string]$FilePath,[string[]]$Arguments)
    $s = New-Object System.Diagnostics.ProcessStartInfo; $s.FileName=$FilePath; $s.UseShellExecute=$false; $s.CreateNoWindow=$true; $s.RedirectStandardOutput=$true; $s.RedirectStandardError=$true
    $p = $s.PSObject.Properties['ArgumentList']
    if ($null -ne $p) { foreach ($a in $Arguments) { [void]$s.ArgumentList.Add([string]$a) } } else { $s.Arguments=(($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ') }
    $process = New-Object System.Diagnostics.Process; $process.StartInfo=$s
    try { if (-not $process.Start()) { throw 'Native process could not be started.' }; $out=$process.StandardOutput.ReadToEndAsync(); $err=$process.StandardError.ReadToEndAsync(); $process.WaitForExit(); [pscustomobject]@{ExitCode=$process.ExitCode;StdOut=$out.Result;StdErr=$err.Result} }
    catch { [pscustomobject]@{ExitCode=1;StdOut='';StdErr=$_.Exception.ToString()} }
    finally { $process.Dispose() }
}
function Invoke-Git { param([Parameter(Mandatory=$true)][string[]]$Arguments) Invoke-NativeProcess -FilePath $git.Source -Arguments $Arguments }
function Get-CommandPath { param([object]$CommandInfo) if ($CommandInfo.Path) {[string]$CommandInfo.Path} else {[string]$CommandInfo.Source} }
function Get-ProjectRelativePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }; $full=[System.IO.Path]::GetFullPath($Path); $r=$rootResolvedPath.TrimEnd([char[]]@(92,47))
    if ($full.Equals($r,[StringComparison]::OrdinalIgnoreCase)) { return '' }
    if ($full.StartsWith($r+[char]92,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($r+[char]47,[StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($r.Length).TrimStart([char[]]@(92,47)).Replace([char]92,[char]47) }
    $full.Replace([char]92,[char]47)
}
function Get-ExistingRelativePath([string]$Path) { if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { Get-ProjectRelativePath $Path } else { $null } }
function Get-FileFingerprint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $i=Get-Item -LiteralPath $Path; $h=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash; return ('{0}|{1}|{2}' -f $i.Length,$i.LastWriteTimeUtc.Ticks,$h) } catch { return $null }
}
function Write-RunnerSummary {
    param([ValidateSet('passed','failed','blocked','not_run')][string]$Status,[string]$Details,[string]$Branch,[string]$BranchAfter,[string]$HeadBefore,[string]$HeadAfter,[string]$TaskRelative,[string]$AgentStatus,[int]$AgentExitCode,[string]$TestStatus,[int]$TestExitCode,[object[]]$TestRuns,[object[]]$AgentRunList=@(),[object[]]$TestRunHistory=@())
    $changed=@(); if ($git) { $d=Invoke-Git @('-C',$root,'diff','--name-only'); $u=Invoke-Git @('-C',$root,'ls-files','--others','--exclude-standard'); foreach($r in @($d,$u)){if($r.ExitCode -eq 0){$changed+=@($r.StdOut -split "`r?`n"|Where-Object{$_}|ForEach-Object{Get-ProjectRelativePath $_})}}; $changed=@($changed|Sort-Object -Unique) }
    $logs=@(); $addLog={param($p) $x=Get-ExistingRelativePath $p; if($x -and $logs -notcontains $x){$logs+=$x}}
    foreach($a in @($AgentRunList)){&$addLog $a.prompt;&$addLog $a.log;&$addLog $a.finalMessage}
    foreach($t in @($TestRunHistory+$TestRuns)){&$addLog (if($t.log){Join-Path $root $t.log}else{$null});&$addLog (if($t.summary){Join-Path $root $t.summary}else{$null});foreach($q in @($t.diagnostics)){&$addLog (if($q){Join-Path $root $q}else{$null})}}
    $summary=[ordered]@{schemaVersion=3;status=$Status;details=$Details;branch=$Branch;git=[ordered]@{branchAfter=$BranchAfter;headBefore=$HeadBefore;headAfter=$HeadAfter};task=$TaskRelative;model=$model;maxRepairAttempts=$maxRepairAttempts;agent=[ordered]@{status=$AgentStatus;exitCode=$AgentExitCode;runs=@($AgentRunList)};tests=[ordered]@{status=$TestStatus;exitCode=$TestExitCode;scopes=@($TestRuns);history=@($TestRunHistory)};changedFiles=@($changed);logs=@($logs)}
    $summary|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Write-Host ("Agent task status: {0}. {1}" -f $Status,$Details); if($Status -eq 'passed'){exit 0};if($Status -eq 'failed'){exit 1};exit 2
}

$taskFullPath=[System.IO.Path]::GetFullPath((if([IO.Path]::IsPathRooted($Task)){$Task}else{Join-Path (Get-Location).Path $Task}));$taskRelative=Get-ProjectRelativePath $taskFullPath
if(-not(Test-Path -LiteralPath $taskFullPath -PathType Leaf)){Write-RunnerSummary blocked ("Task file not found: {0}"-f $taskRelative) '' '' '' '' $taskRelative not_run 2 not_run 2 @()}
$taskResolvedPath=(Resolve-Path -LiteralPath $taskFullPath).Path;$r=$rootResolvedPath.TrimEnd([char[]]@(92,47));$inside=$taskResolvedPath.Equals($r,[StringComparison]::OrdinalIgnoreCase)-or $taskResolvedPath.StartsWith($r+[char]92,[StringComparison]::OrdinalIgnoreCase)-or $taskResolvedPath.StartsWith($r+[char]47,[StringComparison]::OrdinalIgnoreCase)
if(-not $inside){Write-RunnerSummary blocked 'The task file must resolve inside the repository.' '' '' '' '' $taskResolvedPath not_run 2 not_run 2 @()};$taskFullPath=$taskResolvedPath;$taskRelative=Get-ProjectRelativePath $taskFullPath
$required=@('# Goal','# Context','# Requirements','# Acceptance criteria','# Allowed changes','# Forbidden changes','# Required tests');$taskContent=Get-Content -Raw -LiteralPath $taskFullPath;$headings=@($taskContent -split "`r?`n"|Where-Object{$_-match '^# '}|ForEach-Object{$_.TrimEnd()})
if(($headings-join "`n")-ne($required-join "`n")){Write-RunnerSummary failed 'Task file must contain exactly the seven required level-one headings in order.' '' '' '' '' $taskRelative not_run 1 not_run 2 @()}
$m=[regex]::Match($taskContent,'(?ms)^# Required tests[ \t]*\r?\n(?<body>.*?)(?=^# |\z)');if(-not$m.Success){Write-RunnerSummary blocked 'The task must contain a # Required tests section.' '' '' '' '' $taskRelative not_run 2 not_run 2 @()}
$body=[regex]::Replace($m.Groups['body'].Value,'(?s)<!--.*?-->','');$scopes=New-Object 'System.Collections.Generic.List[string]';$bad=$null
foreach($line in @($body -split "`r?`n")){ $line=$line.Trim();if(!$line){continue};if($line -notmatch '^- ([A-Za-z][A-Za-z0-9]*)$'){$bad=$line;break};$n=$Matches[1];if($allowedTestScopes -notcontains $n){$bad=$n;break};if(!$scopes.Contains($n)){[void]$scopes.Add($n)} }
if($bad){Write-RunnerSummary blocked ("Unsupported or malformed required test scope: '{0}'. Allowed scopes: {1}."-f $bad,($allowedTestScopes-join ', ')) '' '' '' '' $taskRelative not_run 2 not_run 2 @()};if($scopes.Count-eq 0){Write-RunnerSummary blocked 'The # Required tests section must contain an allowlisted scope.' '' '' '' '' $taskRelative not_run 2 not_run 2 @()};$scopes=@($scopes)
$agentsPath=Join-Path $root 'AGENTS.md';if(-not(Test-Path $agentsPath -PathType Leaf)){Write-RunnerSummary failed 'AGENTS.md was not found.' '' '' '' '' $taskRelative not_run 1 not_run 2 @()};$agentsContent=Get-Content -Raw $agentsPath;if([string]::IsNullOrWhiteSpace($agentsContent)){Write-RunnerSummary failed 'AGENTS.md is empty.' '' '' '' '' $taskRelative not_run 1 not_run 2 @()}
$git=Get-Command git -ErrorAction SilentlyContinue;if(!$git){Write-RunnerSummary blocked 'Git is required.' '' '' '' '' $taskRelative not_run 2 not_run 2 @()}
$repo=Invoke-Git @('-C',$root,'rev-parse','--show-toplevel');$repoRoot=$repo.StdOut.Trim();if($repo.ExitCode-ne 0-or !$repoRoot){Write-RunnerSummary failed ("Git repository detection failed: {0}"-f $repo.StdErr.Trim()) '' '' '' '' $taskRelative not_run 1 not_run 2 @()};if([IO.Path]::GetFullPath($repoRoot)-ne$root){Write-RunnerSummary failed 'The runner must execute from the repository root.' '' '' '' '' $taskRelative not_run 1 not_run 2 @()}
$b=Invoke-Git @('-C',$root,'branch','--show-current');$branch=$b.StdOut.Trim();if($b.ExitCode-ne 0-or !$branch){Write-RunnerSummary failed ("Git branch detection failed: {0}"-f $b.StdErr.Trim()) '' '' '' '' $taskRelative not_run 1 not_run 2 @()};if($branch-eq'main'){Write-RunnerSummary blocked 'The task runner is disabled on main.' $branch $branch '' '' $taskRelative not_run 2 not_run 2 @()}
$wt=Invoke-Git @('-C',$root,'status','--porcelain=v1','--untracked-files=all');if($wt.ExitCode-ne 0){Write-RunnerSummary failed ("Git working tree inspection failed: {0}"-f $wt.StdErr.Trim()) $branch $branch '' '' $taskRelative not_run 1 not_run 2 @()};if(@($wt.StdOut -split "`r?`n"|Where-Object{$_}).Count-gt 0){Write-RunnerSummary blocked 'The working tree is not clean.' $branch $branch '' '' $taskRelative not_run 2 not_run 2 @()}
$hb=Invoke-Git @('-C',$root,'rev-parse','--verify','HEAD');$headBefore=$hb.StdOut.Trim();if($hb.ExitCode-ne 0-or !$headBefore){Write-RunnerSummary failed ("Could not record Git HEAD: {0}"-f $hb.StdErr.Trim()) $branch $branch '' '' $taskRelative not_run 1 not_run 2 @()}
$cmd=@(Get-Command codex.cmd -All -ErrorAction SilentlyContinue|Where-Object{$_.CommandType-eq'Application'})|Select-Object -First 1;$codexCandidates=@();if($cmd){$codexExecutablePath=Get-CommandPath $cmd;$codexExecutableKind='codex.cmd (preferred)'}else{$codexCandidates=@(Get-Command codex -All -ErrorAction SilentlyContinue);$native=@($codexCandidates|Where-Object{$_.CommandType-eq'Application'-(Get-CommandPath $_)-notmatch '(?i)\.ps1$'})|Select-Object -First 1;if($native){$codexExecutablePath=Get-CommandPath $native;$codexExecutableKind='codex native executable'}}
if(!$codexExecutablePath){$script=@($codexCandidates|Where-Object{$_.CommandType-eq'ExternalScript'-(Get-CommandPath $_)-match '(?i)\.ps1$'})|Select-Object -First 1;if($script){Write-RunnerSummary blocked 'Codex was found only as codex.ps1; ExecutionPolicy will not be changed.' $branch $branch $headBefore $headBefore $taskRelative blocked 2 not_run 2 @()};Write-RunnerSummary blocked 'Codex CLI was not found on PATH.' $branch $branch $headBefore $headBefore $taskRelative blocked 2 not_run 2 @()}
$h1=&$codexExecutablePath --help 2>&1|Out-String;$e1=$LASTEXITCODE;$h2=&$codexExecutablePath exec --help 2>&1|Out-String;$e2=$LASTEXITCODE;$ht=$h1+"`n"+$h2;if($e1-ne 0-or$e2-ne 0-or$ht-notmatch'--model'-or$ht-notmatch'--sandbox'-or$ht-notmatch'--json'-or$ht-notmatch'--output-last-message'){Write-RunnerSummary blocked 'The selected Codex executable lacks the required non-interactive flags.' $branch $branch $headBefore $headBefore $taskRelative blocked 2 not_run 2 @()}

$testPowerShell=Get-Command pwsh -ErrorAction SilentlyContinue;if(!$testPowerShell){$testPowerShell=Get-Command powershell -ErrorAction SilentlyContinue};$testScript=Join-Path $root 'scripts/test.ps1';if(!$testPowerShell-or!(Test-Path $testScript -PathType Leaf)){Write-RunnerSummary blocked 'PowerShell or scripts/test.ps1 is unavailable.' $branch $branch $headBefore $headBefore $taskRelative blocked 2 blocked 2 @()}
$tracked=Join-Path $root 'reports/test-summary.json';$stub=Join-Path ([IO.Path]::GetTempPath()) 'stub_load_log.txt'
function Get-ScopeConfig { param([string]$Name,[int]$Attempt);$suffix=if($Attempt-eq 0){''}else{"-repair-$Attempt"};switch($Name){'BslOnly'{[pscustomobject]@{Name=$Name;Arg='-BslOnly';Log=Join-Path $reportDir ("test-bsl{0}.log"-f $suffix);Summary=Join-Path $reportDir ("test-bsl{0}-summary.json"-f $suffix)}}'EpfBuildOnly'{[pscustomobject]@{Name=$Name;Arg='-EpfBuildOnly';Log=Join-Path $reportDir ("test-epf{0}.log"-f $suffix);Summary=Join-Path $reportDir ("test-epf{0}-summary.json"-f $suffix)}}default{throw "No test mapping for $Name"}}}
function Invoke-TestScope { param([string]$Name,[string]$Arg,[string]$Log,[string]$Summary,[int]$Attempt)
    Remove-Item -Force -ErrorAction SilentlyContinue $Log,$Summary; $before=if($Name-eq'EpfBuildOnly'){Get-FileFingerprint $stub}else{$null};$out=@();$code=1
    try{$out=@(&$testPowerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $testScript $Arg 2>&1);$code=$LASTEXITCODE;$out|ForEach-Object{[string]$_}|Set-Content $Log -Encoding UTF8}catch{Set-Content $Log $_.Exception.ToString() -Encoding UTF8}
    $status='failed';if(Test-Path $tracked -PathType Leaf){try{$j=Get-Content -Raw $tracked|ConvertFrom-Json;$status=[string]$j.status}catch{$status='failed'}}elseif($code-eq 2){$status='blocked'}
    if($status-notin @('passed','failed','blocked')){$status=if($code-eq 2){'blocked'}else{'failed'}}
    $diagnostics=@();if($Name-eq'EpfBuildOnly'){$after=Get-FileFingerprint $stub;if($after-and$after-ne$before){$copy=Join-Path $reportDir ("epf-stub-load-attempt-{0}.log"-f $Attempt);Copy-Item $stub $copy -Force;$diagnostics+=Get-ProjectRelativePath $copy}}
    [pscustomobject]@{scope=$Name;status=$status;exitCode=$code;log=Get-ExistingRelativePath $Log;summary=Get-ExistingRelativePath $Summary;diagnostics=@($diagnostics)}
}
function Invoke-SelectedTests { param([int]$Attempt);$r=@();foreach($n in $scopes){$c=Get-ScopeConfig $n $Attempt;Remove-Item -Force -ErrorAction SilentlyContinue $tracked;$x=Invoke-TestScope $c.Name $c.Arg $c.Log $c.Summary $Attempt;if(Test-Path $tracked -PathType Leaf){Copy-Item $tracked $c.Summary -Force};$r+=$x};$r }
function Get-TestStatus([object[]]$Runs){$s=@($Runs|ForEach-Object{$_.status});if($s-contains'blocked'-or$s-contains'not_run'){'blocked'}elseif($s-contains'failed'){'failed'}else{'passed'}}
function Invoke-Agent { param([string]$Prompt,[int]$Attempt)
    $tag=if($Attempt-eq 0){'initial'}else{"repair-$Attempt"};$pp=Join-Path $reportDir ("prompt-{0}.md"-f $tag);$lp=Join-Path $reportDir ("codex-{0}.jsonl"-f $tag);$fp=Join-Path $reportDir ("codex-{0}-final.md"-f $tag);Set-Content $pp $Prompt -Encoding UTF8;$old=@($env:GIT_CONFIG_COUNT,$env:GIT_CONFIG_KEY_0,$env:GIT_CONFIG_VALUE_0,$env:GIT_TERMINAL_PROMPT);$env:GIT_CONFIG_COUNT='1';$env:GIT_CONFIG_KEY_0='remote.origin.pushurl';$env:GIT_CONFIG_VALUE_0='DISABLED_BY_AGENT_TASK_RUNNER';$env:GIT_TERMINAL_PROMPT='0';$code=1
    try{Push-Location $root;$o=@(Get-Content -Raw $pp|&$codexExecutablePath exec --model $model --sandbox workspace-write --json --output-last-message $fp - 2>&1);$code=$LASTEXITCODE;$o|Set-Content $lp -Encoding UTF8}catch{Set-Content $lp $_.Exception.ToString() -Encoding UTF8}finally{Pop-Location;if($null-eq$old[0]){Remove-Item Env:GIT_CONFIG_COUNT -ErrorAction SilentlyContinue}else{$env:GIT_CONFIG_COUNT=$old[0]};if($null-eq$old[1]){Remove-Item Env:GIT_CONFIG_KEY_0 -ErrorAction SilentlyContinue}else{$env:GIT_CONFIG_KEY_0=$old[1]};if($null-eq$old[2]){Remove-Item Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue}else{$env:GIT_CONFIG_VALUE_0=$old[2]};if($null-eq$old[3]){Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue}else{$env:GIT_TERMINAL_PROMPT=$old[3]}}
    $text=if(Test-Path $lp){Get-Content -Raw $lp}else{''};$status=if($code-eq 0){'passed'}elseif($text-match'(?i)(unknown model|unsupported.*model|invalid.*model)'){'blocked'}else{'failed'};[pscustomobject]@{attempt=$Attempt;status=$status;exitCode=$code;prompt=Get-ExistingRelativePath $pp;log=Get-ExistingRelativePath $lp;finalMessage=Get-ExistingRelativePath $fp}
}
function Verify-AgentGit { $h=Invoke-Git @('-C',$root,'rev-parse','--verify','HEAD');$b=Invoke-Git @('-C',$root,'branch','--show-current');[pscustomobject]@{ok=($h.ExitCode-eq 0-and$b.ExitCode-eq 0-and$h.StdOut.Trim()-eq$headBefore-and$b.StdOut.Trim()-eq$branch);head=$h.StdOut.Trim();branch=$b.StdOut.Trim();error=("HEAD: {0}; branch: {1}"-f $h.StdErr.Trim(),$b.StdErr.Trim())} }
function New-InitialPrompt { @"
You are the implementation agent for the current repository.
Read and obey AGENTS.md and the selected task below. Work only on branch $branch.
Treat # Allowed changes and # Forbidden changes as authoritative. Do not make unrelated changes.
Do not run git push, git merge, create a pull request, switch to main, or commit. Run the selected allowlisted tests and make the minimum changes needed for the acceptance criteria.
The runner will execute only: $($scopes -join ', '). Do not claim success unless every selected scope passes.
===== AGENTS.md =====
$agentsContent
===== SELECTED TASK: $taskRelative =====
$taskContent
"@ }
function New-RepairPrompt { param([object[]]$Runs,[int]$Attempt);$lines=@("Repair attempt $Attempt of $maxRepairAttempts.",'The previous selected test run failed. First inspect the existing diagnostic files listed below. Do not paste or assume full logs from this prompt; read them locally.','Fix the minimum cause of the failure; do not rewrite the whole solution without necessity. Re-check the task acceptance criteria and make no commit/push/merge.','Required test statuses:');foreach($x in $Runs){$lines+="- $($x.scope): $($x.status)";if($x.log){$lines+="  log: $($x.log)"};if($x.summary){$lines+="  summary: $($x.summary)"};foreach($q in @($x.diagnostics)){if($q){$lines+="  diagnostic: $q"}}};@"
You are repairing the current repository after a failed selected test run.
$($lines -join "`n")
Read those files before editing. In particular, use the full EPF/1C diagnostic if present. Then fix the minimal cause, rerun the selected tests, and satisfy the original acceptance criteria.
Do not run git push, git merge, create a pull request, switch to main, or commit.
===== AGENTS.md =====
$agentsContent
===== ORIGINAL TASK: $taskRelative =====
$taskContent
"@ }

$initial=Invoke-Agent (New-InitialPrompt) 0;$agentRuns+=@($initial);$verify=Verify-AgentGit;$headAfter=$verify.head;$branchAfter=$verify.branch
if(-not$verify.ok){Write-RunnerSummary failed ("Codex changed HEAD/branch or Git verification failed. {0}"-f $verify.error) $branch $branchAfter $headBefore $headAfter $taskRelative $initial.status $initial.exitCode not_run 2 @() $agentRuns}
if($initial.status-eq'blocked'){Write-RunnerSummary blocked 'Initial Codex run was blocked.' $branch $branchAfter $headBefore $headAfter $taskRelative blocked $initial.exitCode not_run 2 @() $agentRuns}
if($initial.status-eq'failed'){Write-RunnerSummary failed 'Initial Codex run failed.' $branch $branchAfter $headBefore $headAfter $taskRelative failed $initial.exitCode not_run 2 @() $agentRuns}
$testRuns=Invoke-SelectedTests 0;$testStatus=Get-TestStatus $testRuns;$testHistory+=@($testRuns)
$attempt=0
while($testStatus-eq'failed'-and$attempt-lt$maxRepairAttempts){$attempt++;$repair=Invoke-Agent (New-RepairPrompt $testRuns $attempt) $attempt;$agentRuns+=@($repair);$verify=Verify-AgentGit;$headAfter=$verify.head;$branchAfter=$verify.branch;if(-not$verify.ok){Write-RunnerSummary failed ("Repair changed HEAD/branch or Git verification failed. {0}"-f $verify.error) $branch $branchAfter $headBefore $headAfter $taskRelative failed $repair.exitCode $testStatus 1 $testRuns $agentRuns $testHistory};if($repair.status-eq'blocked'){Write-RunnerSummary blocked 'Repair agent was blocked.' $branch $branchAfter $headBefore $headAfter $taskRelative blocked $repair.exitCode $testStatus 2 $testRuns $agentRuns $testHistory};if($repair.status-eq'failed'){Write-RunnerSummary failed 'Repair agent failed.' $branch $branchAfter $headBefore $headAfter $taskRelative failed $repair.exitCode $testStatus 1 $testRuns $agentRuns $testHistory};$testRuns=Invoke-SelectedTests $attempt;$testStatus=Get-TestStatus $testRuns;$testHistory+=@($testRuns)}
$agentStatus=if($agentRuns[-1].status-eq'passed'){'passed'}else{$agentRuns[-1].status};$exit=if($testStatus-eq'passed'){0}elseif($testStatus-eq'failed'){1}else{2};$overall=if($testStatus-eq'blocked'){'blocked'}elseif($testStatus-eq'failed'){'failed'}else{'passed'};$details=if($overall-eq'passed'){'Codex completed; all selected scopes passed.'}elseif($overall-eq'blocked'){'A selected scope was blocked; no further repair was attempted.'}else{"Selected tests still failed after $attempt repair attempt(s)."}
Write-RunnerSummary $overall $details $branch $branchAfter $headBefore $headAfter $taskRelative $agentStatus $agentRuns[-1].exitCode $testStatus $exit $testRuns $agentRuns $testHistory
