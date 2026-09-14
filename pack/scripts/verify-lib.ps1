#Requires -Version 5.1
<#
.SYNOPSIS
  Shared path-policy predicates for the pack's verify scripts (WQ-441).

.DESCRIPTION
  Dot-source this from any verify script:

      . (Join-Path $PSScriptRoot 'verify-lib.ps1')

  Four scripts had each hand-rolled their own answer to "is this a real machine path or a placeholder",
  and the answers differed. That is how WQ-440 happened: `verify-session-handoff.ps1` arrived in 2.22.68
  with no path rule at all, while the lesson it needed had been encoded in `verify-agent-handoffs.ps1`
  since 2.22.58 - in a *different* rule, so there was nothing to copy and nothing to notice missing.

  The rules themselves are genuinely different and stay in their own scripts:

    - a session opener **must** be root-anchored (absolute or placeholder), or it opens the wrong file
    - `SESSION.md` **must not** contain an absolute path, because it travels between machines
    - a doc **may** show an absolute example path when it is plainly an illustration

  What they share is the vocabulary underneath: what counts as a substitution marker, what counts as an
  absolute path on either platform, and which names are illustrations rather than people. Those live here,
  once. Behavior step 59 fails when a script outside the manifest allowlist grows its own copy.
#>

# A file that is dot-sourced more than once must not redefine anything at a cost, so this is idempotent.
$script:PackVerifyLibLoaded = $true

# Windows drive-letter paths and the two POSIX home roots. The negative lookbehind keeps `%VAR%\C:\x`-style
# fragments and `$env:` expressions from registering as bare machine paths.
$script:PackAbsolutePathPattern =
    '(?m)(?<![A-Za-z0-9%$])([A-Za-z]:\\[^\s`''"|)\]]+|/home/[^\s`''"|)\]]+|/Users/[^\s`''"|)\]]+)'

# Names the docs use *as* examples. Real user names must fail; these must not, or the convention the pack
# tells people to follow becomes unwritable. Kept here so behavior step 50 and the Illustrative policy
# cannot drift apart.
$script:PackIllustrationUserNames = @('alice', 'bob', 'dev', 'you', 'user', 'username', 'yourname', 'name')

# Path fragments that mark an example location rather than somebody's disk.
$script:PackIllustrationMarkers = @(
    'path\to', 'path/to', 'your-repo', 'your_repo', 'yourrepo', 'my-app', 'myapp', 'example', '...'
)

function Get-PackIllustrationUserName {
    <#.SYNOPSIS Canonical illustration user names, for identity scans.#>
    return @($script:PackIllustrationUserNames)
}

# How a behavior step announces itself: Write-Host "`nN. title". One home for the pattern, because the
# coverage guard and the mutation runner both have to agree on what a step *is*. The closing delimiter
# must be the same quote the announcement opened with - titles contain apostrophes ("'Is this a git work
# tree' is asked of git"), and stripping from the first quote of any kind silently blanks those titles.
$script:PackBehaviorStepPattern = 'Write-Host\s+(?<q>["''])(?:`n)*(?<num>\d+)\.\s*(?<title>.*?)\k<q>\s*$'

function Get-PackBehaviorStepAnnouncement {
    <#
    .SYNOPSIS
      Every step a behavior suite announces, as objects with step, title and line.
    .DESCRIPTION
      Reads the suite's source, not its output, so the answer does not depend on a run. Used by the
      WQ-443 coverage guard to compare the suite against its control registry.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$SuiteText)
    if ([string]::IsNullOrWhiteSpace($SuiteText)) { return @() }
    $found = @()
    $lines = $SuiteText -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], $script:PackBehaviorStepPattern)
        if (-not $m.Success) { continue }
        $found += [pscustomobject]@{
            Step  = [int]$m.Groups['num'].Value
            Title = $m.Groups['title'].Value.Trim()
            Line  = $i + 1
        }
    }
    return @($found)
}

function Resolve-PackBehaviorStep {
    <#
    .SYNOPSIS
      The step a given source line belongs to: the last announcement at or before it. $null when the
      line precedes every announcement.
    .DESCRIPTION
      Attribution for WQ-443's mutation runner, which has to know *which* step went red rather than
      that something did. Deliberately not derived from the suite's output: a planted control invokes
      child verifies whose output carries the same `[FAIL]` prefix, and a trial parse of one run
      attributed five failures to two steps when the suite's own count was one. Working from the call
      site instead means only a real `Fail` is ever recorded.

      Kept as a pure line-to-step function so a behavior step can plant controls against it in-process
      instead of shelling out - the recursion step 70 fell into.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Announcements,
        [Parameter(Mandatory = $true)][int]$Line
    )
    if ($null -eq $Announcements) { return $null }
    $best = $null
    foreach ($a in @($Announcements)) {
        $aLine = [int]$a.Line
        if ($aLine -le $Line) {
            if ($null -eq $best -or $aLine -gt [int]$best.Line) { $best = $a }
        }
    }
    if ($null -eq $best) { return $null }
    return [int]$best.Step
}

function Get-PackRequestedStepNumber {
    <#
    .SYNOPSIS
      Step numbers a maintainer asked for, from whatever the shell handed over. Returns a Numbers
      list and an Unreadable list.
    .DESCRIPTION
      `-File` makes every argument a string, and `[int[]]'4,7'` does not throw - it returns **47**,
      because .NET reads the comma as a digit-group separator. A run asked for steps 4 and 7 proved
      step 47 and exited 0, reporting success for work nobody requested. Pairs of two-digit steps
      escaped only by luck: '15,18' makes 1518, which is not a step, so that one failed loudly.

      So the split happens here, on the comma, and anything that is not an integer is returned as
      unreadable rather than coerced into one.
    #>
    param([Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][string[]]$Tokens)
    $numbers = @()
    $unreadable = @()
    foreach ($token in (@($Tokens) -join ',').Split(',')) {
        $t = "$token".Trim()
        if (-not $t) { continue }
        $n = 0
        if ([int]::TryParse($t, [ref]$n)) { $numbers += $n } else { $unreadable += $t }
    }
    return [pscustomobject]@{ Numbers = @($numbers); Unreadable = @($unreadable) }
}

function Get-PackMutationAction {
    <#
    .SYNOPSIS
      Which action a mutation spec asks for. Absent means `replace`, which is what every spec written
      before the second action existed means.
    .DESCRIPTION
      One reader, three callers: the spec validator, the registry shape check, and the runner that
      applies it. Left to themselves they would each default differently the first time a spec omitted
      the field, and a spec the registry accepted would then be applied as something else.
    #>
    param([Parameter(Mandatory = $true)][AllowNull()]$Spec)
    if ($null -eq $Spec) { return 'replace' }
    $action = [string]$Spec.action
    if ([string]::IsNullOrWhiteSpace($action)) { return 'replace' }
    return $action
}

function Get-PackMutationSpecProblem {
    <#
    .SYNOPSIS
      Reasons a registry mutation spec cannot be applied as written. Empty means it is applicable.
    .DESCRIPTION
      A mutation that changes nothing leaves the suite green, and a green suite reads as a passing
      proof - so an unapplicable spec must be an error, never a skip. This pack shipped
      `.Replace(a,b,1)` three times where the replacement was a no-op and the guard above it reported
      success, which is the same defect one layer up.

      Requiring **exactly one** occurrence is deliberate. Zero means the spec is stale, and more than
      one means the runner cannot say which site it broke, so a step going red proves less than it
      appears to.

      Three actions, because a guard's subject is not always the text of a file. Step 4 keeps an
      orphan duplicate template *out* of the pack and step 7 requires two docs to be *there*; no edit
      to any existing file can break either, so with `replace` as the only action both are unprovable
      for a reason that says nothing about the step. `create` writes a file the tree does not have
      and `delete` removes one it does, and their stale cases are mirror images of each other and of
      a find that matches zero times: a create whose target already exists, or a delete whose target
      is already gone, describes a tree in which the guard should already be red.
    .PARAMETER Root
      The tree to resolve the spec's relative file path against - normally a disposable copy.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Spec,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Root
    )
    if ($null -eq $Spec) { return @('mutation spec is missing') }
    $problems = @()
    $file = [string]$Spec.file
    $find = [string]$Spec.find
    $replace = [string]$Spec.replace
    $action = Get-PackMutationAction -Spec $Spec

    if ([string]::IsNullOrWhiteSpace($file)) { $problems += 'spec names no file' }
    if (@('replace', 'create', 'delete') -notcontains $action) {
        $problems += "spec has action '$action', which the runner cannot apply - use replace, create or delete"
    }
    if ($action -eq 'create' -or $action -eq 'delete') {
        if ($action -eq 'create' -and [string]::IsNullOrWhiteSpace([string]$Spec.content)) {
            $problems += 'a create spec has no content to write'
        }
        if ($problems.Count -gt 0) { return @($problems) }
        if ([string]::IsNullOrWhiteSpace($Root)) { return @('no root to resolve the spec against') }
        $whole = Join-Path $Root ($file -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $present = Test-Path -LiteralPath $whole
        if ($action -eq 'create' -and $present) {
            return @("create target already exists: $file - the guard asserts this file is absent, so a tree that has it is already broken")
        }
        if ($action -eq 'delete' -and -not $present) {
            return @("delete target is already absent: $file - the guard asserts this file is present, so a tree without it is already broken")
        }
        return @()
    }
    if ([string]::IsNullOrWhiteSpace($find)) { $problems += 'spec has an empty find' }
    if ($find -eq $replace) { $problems += 'find and replace are identical, so applying it would change nothing' }
    if ($problems.Count -gt 0) { return @($problems) }

    if ([string]::IsNullOrWhiteSpace($Root)) { return @('no root to resolve the spec against') }
    $full = Join-Path $Root ($file -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $full)) { return @("target file not found: $file") }

    $text = Get-Content -LiteralPath $full -Raw -Encoding UTF8
    if ($null -eq $text) { $text = '' }
    $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
    if ($count -ne 1) {
        $problems += "find occurs $count time(s) in $file, needs exactly 1 - a stale or ambiguous spec cannot prove anything"
    }
    return @($problems)
}

function Resolve-PackMutationFailureStep {
    <#
    .SYNOPSIS
      Failure records with their step filled in from the recorded line, using the caller's own parser.
    .DESCRIPTION
      A mutation can break the very code the suite uses to attribute its own failures, and this is not
      hypothetical: the first run of verify-guard-proofs.ps1 reported step 72 as **not proven** because
      step 72's mutation disables `Resolve-PackBehaviorStep`. The suite failed exactly as intended and
      recorded every failure with no step, so the run could not name what it had broken - a proof
      defeated by the thing it was proving.

      So the runner re-attributes from the raw line number, parsing the mutated copy's suite text with
      its **own** unmutated functions. Only the text comes from the copy, which is why a mutation
      inside `verify-lib.ps1` cannot blind the measurement.
    .PARAMETER SuiteText
      Source of the suite that produced these results - the copy's, so the lines match what ran.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Results,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SuiteText
    )
    if ($null -eq $Results) { return @() }
    $announced = @(Get-PackBehaviorStepAnnouncement -SuiteText $SuiteText)
    $out = @()
    foreach ($f in @($Results.failures)) {
        $step = $null
        if ($null -ne $f.step) { $step = [int]$f.step }
        elseif ($null -ne $f.line -and [int]$f.line -gt 0) {
            $step = Resolve-PackBehaviorStep -Announcements $announced -Line ([int]$f.line)
        }
        $out += [pscustomobject]@{ step = $step; line = $f.line; message = $f.message }
    }
    return @($out)
}

function Test-PackMutationOutcome {
    <#
    .SYNOPSIS
      Whether a mutated run actually proved the steps it was supposed to. Empty result means proven.
    .DESCRIPTION
      The outcome that matters is not "the suite failed" but "these steps failed". A mutation that
      breaks something unrelated would otherwise count as a proof, which is how a control ends up
      observing the wrong thing entirely - the WQ-443 shape.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Results,
        [Parameter(Mandatory = $true)][AllowNull()]$ExpectFailIn
    )
    if ($null -eq $Results) { return @('the mutated run produced no results file') }
    $expected = @($ExpectFailIn)
    if ($expected.Count -eq 0) { return @('nothing was expected to fail, so the run proves nothing') }

    $problems = @()
    if ([int]$Results.failCount -eq 0) {
        $problems += 'the suite stayed green under the mutation - the step is not reading what it claims to'
    }
    $failedSteps = @(@($Results.failures) | Where-Object { $null -ne $_.step } | ForEach-Object { [int]$_.step })
    foreach ($e in $expected) {
        if ($failedSteps -notcontains [int]$e) {
            $problems += "step $e did not report a failure under its own mutation"
        }
    }
    return @($problems)
}

function Get-PackBehaviorControlProblem {
    <#
    .SYNOPSIS
      Disagreements between a behavior suite and its WQ-443 control registry. Empty means they agree.
    .DESCRIPTION
      WQ-443 exists because six guards in one day reported success while observing nothing. The fix
      cannot itself be a guard that only looks like one, so this deliberately does *not* try to detect
      a control by reading the step's code: three legitimate idioms are in use (plant-and-restore, an
      expectations table with both polarities, and a negative fixture), and a scan wide enough to
      accept all three also accepts a comment that merely claims one. Proven, not assumed - a
      heuristic classifier scored step 69 as having no control while it carries seven.

      So the registry is the declaration and this compares two lists exactly. What makes the
      declaration hard to fake is the seal: a closed reason is valid only at or below
      schemaSealedAtStep, so a newly added step must carry a `mutation` spec or argue
      `not-applicable` in writing - it cannot inherit the grandfathering that covers the steps
      written before the registry existed.
    .PARAMETER Registry
      The parsed behavior-controls.json object. Pass $null to report it as unreadable rather than
      throwing - an absent registry must fail loudly, not skip.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SuiteText,
        [Parameter(Mandatory = $true)][AllowNull()]$Registry
    )

    if ($null -eq $Registry) { return @('control registry is missing or unparsable') }

    $problems = @()
    $announced = @(Get-PackBehaviorStepAnnouncement -SuiteText $SuiteText)
    if ($announced.Count -eq 0) { $problems += 'no step announcements found in the suite - the announcement shape changed and this guard went blind' }

    $entries = @($Registry.steps)
    if ($entries.Count -eq 0) { $problems += 'control registry lists no steps' }

    $seal = -1
    if ($null -ne $Registry.schemaSealedAtStep) { $seal = [int]$Registry.schemaSealedAtStep }
    else { $problems += 'control registry has no schemaSealedAtStep - without it a closed reason is valid forever' }

    $closed = @()
    if ($null -ne $Registry.closedReasons) { $closed = @($Registry.closedReasons) }
    $knownReasons = @()
    if ($null -ne $Registry.reasonVocabulary) { $knownReasons = @($Registry.reasonVocabulary.PSObject.Properties.Name) }

    # Duplicates first: every later comparison assumes one entry per number.
    foreach ($g in @($announced | Group-Object Step | Where-Object { $_.Count -gt 1 })) {
        $problems += "step $($g.Name) is announced $($g.Count) times in the suite"
    }
    foreach ($g in @($entries | Group-Object step | Where-Object { $_.Count -gt 1 })) {
        $problems += "step $($g.Name) appears $($g.Count) times in the control registry"
    }

    $entryByStep = @{}
    foreach ($e in $entries) { if (-not $entryByStep.ContainsKey([int]$e.step)) { $entryByStep[[int]$e.step] = $e } }

    # The check WQ-443 is for: a step that exists and declares nothing.
    foreach ($a in $announced) {
        if (-not $entryByStep.ContainsKey($a.Step)) {
            $problems += ("step $($a.Step) ('$($a.Title)') is not in the control registry - add an entry " +
                "declaring how it is proven able to fail, or why it cannot be (pack/audit/behavior-controls.json)")
        }
    }

    $announcedByStep = @{}
    foreach ($a in $announced) { if (-not $announcedByStep.ContainsKey($a.Step)) { $announcedByStep[$a.Step] = $a } }
    foreach ($e in $entries) {
        if (-not $announcedByStep.ContainsKey([int]$e.step)) {
            $problems += "control registry declares step $($e.step), which the suite does not announce - renumbered or removed"
        }
    }

    foreach ($e in $entries) {
        $num = [int]$e.step
        $where = "step $num"

        # A title copied into the registry would drift silently, so the copy is a checked invariant.
        if ($announcedByStep.ContainsKey($num)) {
            $liveTitle = $announcedByStep[$num].Title
            if ($e.title -ne $liveTitle) {
                $problems += "$where title disagrees - registry '$($e.title)' vs suite '$liveTitle'"
            }
        }

        $status = ''
        if ($null -ne $e.status) { $status = [string]$e.status }
        if ($status -ne 'mutation' -and $status -ne 'exempt') {
            $problems += "$where has status '$status' - must be mutation or exempt"
            continue
        }

        # Note the status is `mutation`, not `proven`. A file cannot hold a proof: the moment the
        # runner is not run, a stored "proven" is a stale claim, which is the WQ-460 shape. The
        # registry holds the *specification*; the proof is the runner's exit code on the day it runs.
        if ($status -eq 'mutation') {
            if ($null -eq $e.mutation) { $problems += "$where declares a mutation but carries no spec for the runner to apply" }
            else {
                $action = Get-PackMutationAction -Spec $e.mutation
                if ($action -eq 'create') {
                    # A guard over an absence is broken by adding the file, not by editing one. The
                    # fields differ, so checking a create spec against the replace fields would demand
                    # a `find` that has nothing to search.
                    foreach ($k in @('file', 'content')) {
                        if ([string]::IsNullOrWhiteSpace([string]$e.mutation.$k)) {
                            $problems += "$where create mutation has no '$k'"
                        }
                    }
                } elseif ($action -eq 'delete') {
                    if ([string]::IsNullOrWhiteSpace([string]$e.mutation.file)) {
                        $problems += "$where delete mutation has no 'file'"
                    }
                } elseif ($action -eq 'replace') {
                    foreach ($k in @('file', 'find', 'replace')) {
                        if ([string]::IsNullOrWhiteSpace([string]$e.mutation.$k)) {
                            $problems += "$where mutation spec has no '$k'"
                        }
                    }
                    if (([string]$e.mutation.find) -eq ([string]$e.mutation.replace)) {
                        # The `.Replace(a,b,1)` no-op that shipped three times: a mutation that changes
                        # nothing leaves the suite green and reads as a passing proof.
                        $problems += "$where mutation find and replace are identical - it would change nothing and pass"
                    }
                } else {
                    $problems += "$where mutation declares action '$action', which the runner cannot apply - use replace, create or delete"
                }
            }
            if ($null -eq $e.expectFailIn -or @($e.expectFailIn).Count -eq 0) {
                $problems += "$where declares a mutation but names no step that must report FAIL when it is applied"
            }
            continue
        }

        $reason = ''
        if ($null -ne $e.reason) { $reason = [string]$e.reason }
        if (-not $reason) {
            $problems += "$where is exempt with no reason"
            continue
        }
        if ($knownReasons -notcontains $reason) {
            $problems += "$where uses reason '$reason', which is not in the registry's reasonVocabulary"
            continue
        }
        if (($closed -contains $reason) -and ($num -gt $seal)) {
            $problems += ("$where claims the closed reason '$reason' above the seal ($seal) - grandfathering " +
                'does not extend to steps written after the registry; prove it or argue not-applicable')
        }
        if ($reason -eq 'not-applicable' -and [string]::IsNullOrWhiteSpace([string]$e.note)) {
            $problems += "$where claims not-applicable without a note explaining why no mutation can make it fail"
        }
    }

    # WQ-467: which rows are exempt is declared as a list, and the list is compared to the rows. The
    # incident that asks for this is a transition nobody can account for - three rows read `exempt`
    # one hour and carried full mutation specs the next, with the maintainer's own edits covering
    # five rows of eight. The specs were sound (all three were later proven by execution), so the
    # unexplained thing was the *change*, and nothing in the system disagreed with it: the counts are
    # printed, and a printed count nobody recorded is a number, not a check.
    #
    # Naming the steps rather than counting them is deliberate. A count cannot see a swap - one row
    # retrofitted while another regresses to exempt keeps the total intact. It also means the
    # declaration has to be edited in the same change as the status, and that edit is the explanation
    # the incident lacked.
    if ($null -eq $Registry.exemptSteps) {
        $problems += ('control registry has no exemptSteps list - a status change would have nothing to ' +
            'disagree with, which is how three rows changed status unexplained (WQ-467)')
    } else {
        $declaredExempt = @(@($Registry.exemptSteps) | ForEach-Object { [int]$_ } | Sort-Object -Unique)
        $actualExempt = @(@($entries | Where-Object { ([string]$_.status) -eq 'exempt' } |
                    ForEach-Object { [int]$_.step }) | Sort-Object -Unique)
        $nowProven = @($declaredExempt | Where-Object { $actualExempt -notcontains $_ })
        $newlyExempt = @($actualExempt | Where-Object { $declaredExempt -notcontains $_ })
        if ($nowProven.Count -gt 0) {
            $problems += ("exemptSteps declares step(s) $($nowProven -join ', ') exempt, and the registry no longer is - " +
                'a retrofit is good news, so record it in exemptSteps and say where it was proven')
        }
        if ($newlyExempt.Count -gt 0) {
            $problems += ("step(s) $($newlyExempt -join ', ') are exempt without being declared in exemptSteps - " +
                'a row losing its proof must be a deliberate, visible edit')
        }
    }

    return @($problems)
}

function Get-PackCitedReferenceFile {
    <#
    .SYNOPSIS
      The files whose file references are checked: generic rules, skills, pack docs and the workspace
      rules. Changelogs are excluded.
    .DESCRIPTION
      One home for the question "whose advice do we hold to this standard", because two steps ask it -
      step 47 for `pack/`-rooted cites and step 81 for the project-relative ones. Kept together so a
      new document class cannot arrive into one scan and not the other.

      Changelogs describe past state on purpose: a file that existed at 2.22.3 and was renamed later
      is history, not a broken link.
    #>
    param([Parameter(Mandatory = $true)][string]$PackRoot)
    $files = @()
    $files += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/rules') -Filter *.mdc -File
    $files += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/skills') -Filter SKILL.md -File -Recurse
    $files += Get-ChildItem -LiteralPath (Join-Path $PackRoot 'pack/docs') -Filter *.md -File |
        Where-Object { $_.Name -notmatch 'CHANGELOG' }
    $wsRules = Join-Path $PackRoot '.cursor/rules'
    if (Test-Path -LiteralPath $wsRules) {
        $files += Get-ChildItem -LiteralPath $wsRules -Filter *.mdc -File
    }
    return @($files)
}

function Get-PackCitedProjectPathReference {
    <#
    .SYNOPSIS
      `docs/`, `scripts/` and `tests/` paths cited in the given lines. Returns Line and Ref per hit,
      with the separator normalised to a forward slash.
    .DESCRIPTION
      Step 47 resolves `pack/`-rooted cites only, because a doc naming `docs/ROADMAP.md` is usually
      describing the reader's project and this checkout has no roadmap. That left the other three
      roots unchecked, and a cite under them can be just as broken - it is simply broken somewhere
      else, which is what `Get-PackCitedProjectPathProblem` decides.

      Extraction is separate from that judgement so the pattern can be tested without a tree. Two
      details are load-bearing and both cost a false run to find: the extension list is longest-first
      with nothing allowed after it, or `.md.template` truncates to `.md`, and a cite written with
      backslashes (`scripts\apply_version.py`, as a command line naturally is) is the same path as
      one written with slashes.

      `AllowEmptyString` is not decoration: every document here has blank lines, and without it the
      bind fails per file and the scan reports nothing - which is why the live arm demands a minimum
      cite count rather than trusting a clean result.
    #>
    param([Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)
    $extAlt = 'template|mdc|ps1|py|md|json|cmd|bat|sh'
    $rootAlt = 'docs|scripts|tests'
    $rx = "(?<![\w./\\-])((?:$rootAlt)[\\/][\w./\\-]+?\.(?:$extAlt))(?![\w]|\.[A-Za-z]{2,8})"
    $hits = @()
    $lineNo = 0
    foreach ($line in @($Lines)) {
        $lineNo++
        foreach ($m in [regex]::Matches("$line", $rx)) {
            $ref = $m.Groups[1].Value -replace '\\', '/'
            # A path with a placeholder in it is an illustration, not a cite: nothing resolves
            # `docs/<slug>.md` and nothing should try.
            if ($ref -match '[*<>{}$]|MyApp|YourApp') { continue }
            $hits += [pscustomobject]@{ Line = $lineNo; Ref = $ref }
        }
    }
    return @($hits)
}

function Get-PackCitedProjectPathProblem {
    <#
    .SYNOPSIS
      Cites under `docs/`, `scripts/` or `tests/` that send a reader nowhere. Returns Problems plus
      the declared paths it checked and the ones it deliberately did not.
    .DESCRIPTION
      The scan is the easy half. The reason this sat open behind step 47 for so long is that a cite
      under these roots has three possible owners and only one of them is checkable by asking whether
      the file is here:

        * **this checkout** - `docs/WORK_QUEUE.md`, `scripts/audit_code_checks.py`. Must resolve, and
          that is the default for anything undeclared, so a new cite is checked without being listed.
        * **delivered** - the reader's project gets it *from this pack*: `docs/ROADMAP.md` from a
          template, `docs/AGENT_REFRESH.md` from the refresh script. Asking whether it is here is the
          wrong question - the right one is whether the pack can still produce it, which is a stronger
          check than existence, because advice to keep a file no template writes is undeliverable.
        * **the reader's own** - `docs/PRODUCT_REFERENCE.md`, named as "or equivalent". Nothing here
          can check it, so the only honest treatment is to say so out loud and require a reason.

      Ownership is declared per path in `pack/audit/manifest.json` rather than guessed from the citing
      file, because one paragraph cites both trees: `START_HERE.md` line 22 contrasts this repo's work
      queue with a bootstrapped app's roadmap in a single sentence. Guessing from prose was tried and
      rejected for the same reason - that same doc says "there is no `docs/AGENT_SESSION_START.md`
      here", which a negation-sniffing filter reads as an exemption and a reader reads as the truth.

      An indiscriminate pass over these three roots reports 68 findings on a clean tree, every one of
      them correct advice about somebody else's project. That is how the first attempt at this check
      got muted, and a muted check is worse than none - so the exemptions are enumerated, each carries
      a why, and a declaration nothing cites any more is itself a problem.
    .PARAMETER Ownership
      The manifest's `citedPathOwnership` map: path -> owner (`delivered` or `reader`), `deliveredBy`
      for the first, `why` for both.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()]$Reference,
        [Parameter(Mandatory = $true)][AllowNull()]$Ownership,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PackRoot
    )
    $problems = @()
    $declared = @{}
    if ($null -ne $Ownership) {
        foreach ($p in $Ownership.PSObject.Properties) {
            if ($p.Name -like '_*') { continue }
            $declared[$p.Name] = $p.Value
        }
    }

    $cited = @{}
    foreach ($r in @($Reference)) {
        $ref = [string]$r.Ref
        if (-not $ref) { continue }
        if (-not $cited.ContainsKey($ref)) { $cited[$ref] = @() }
        $cited[$ref] += "$($r.Source):$($r.Line)"
    }

    $checkedDelivered = @()
    $unchecked = @()
    foreach ($ref in ($cited.Keys | Sort-Object)) {
        $where = ($cited[$ref] | Sort-Object -Unique) -join ', '
        $decl = $declared[$ref]
        if ($null -eq $decl) {
            $abs = Join-Path $PackRoot ($ref -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $abs)) {
                $problems += ("$ref is cited at $where, is not in this checkout, and is not declared in " +
                    "citedPathOwnership - create it, fix the cite, or declare who owns it")
            }
            continue
        }
        $owner = [string]$decl.owner
        $why = [string]$decl.why
        if ([string]::IsNullOrWhiteSpace($why)) {
            $problems += "citedPathOwnership['$ref'] has no why - an exemption without a reason is how a muted check starts"
        }
        switch ($owner) {
            'delivered' {
                $by = [string]$decl.deliveredBy
                if ([string]::IsNullOrWhiteSpace($by)) {
                    $problems += "citedPathOwnership['$ref'] claims delivered but names no deliveredBy"
                    break
                }
                $byAbs = Join-Path $PackRoot ($by -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $byAbs)) {
                    $problems += ("$ref is cited at $where and declared delivered by $by, which does not exist - " +
                        'the pack cannot produce the file its own advice tells a project to keep')
                } else {
                    $checkedDelivered += "$ref <- $by"
                }
            }
            'reader' { $unchecked += "$ref ($why)" }
            default {
                $problems += ("citedPathOwnership['$ref'] has owner '$owner', which means nothing here - " +
                    'use delivered (the pack writes it into a project) or reader (the project owns it)')
            }
        }
    }

    foreach ($ref in ($declared.Keys | Sort-Object)) {
        if (-not $cited.ContainsKey($ref)) {
            $problems += ("citedPathOwnership declares $ref, which no rule, skill or doc cites any more - " +
                'a stale exemption silently covers whatever is cited next')
        }
    }

    return [pscustomobject]@{
        Problems  = @($problems)
        Delivered = @($checkedDelivered | Sort-Object)
        Unchecked = @($unchecked | Sort-Object)
        Cited     = $cited.Count
    }
}

function Get-PackPosixPortabilityHit {
    <#
    .SYNOPSIS
      Constructs in a shell script that work on Linux and fail on macOS. Empty means portable.
    .DESCRIPTION
      macOS is not "Linux, near enough" (WQ-436 found 16 real failures against an estimate of 24
      different ones). Two families cause most of it, and both are decidable by reading the script:

        * **GNU coreutils that macOS does not ship** - `sha256sum`, `md5sum`, `timeout`, GNU-only flags
          like `stat -c`, `sed -i` with no backup argument, `grep -P`, `date -d`, `find -printf`.
        * **bash 4 syntax** - macOS ships bash 3.2 and will not be updated, so `mapfile`, `declare -A`,
          `${v^^}` and `**/` globs are unavailable no matter how current the machine is.

      Checking this statically matters because the alternative is a macOS runner, and the maintainer of
      this pack has no Mac. It does not make a macOS run unnecessary - a case-insensitive filesystem
      and a `pwsh` that has to be installed are not visible in the text - but it removes the part that
      is, so what remains genuinely needs the hardware.
    .PARAMETER Text
      Whole script text. Comment lines are ignored: naming a construct in prose is not calling it.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $rules = @(
        @{ Name = 'sha256sum (macOS has shasum -a 256)'; Pattern = '(?<![\w-])sha256sum(?![\w-])' },
        @{ Name = 'md5sum (macOS has md5)'; Pattern = '(?<![\w-])md5sum(?![\w-])' },
        @{ Name = 'timeout (GNU coreutils, absent on macOS)'; Pattern = '(?<![\w-])timeout\s+\d' },
        @{ Name = 'readlink -f (absent on older macOS)'; Pattern = '(?<![\w-])readlink\s+-\w*f' },
        @{ Name = 'stat -c (BSD stat uses -f)'; Pattern = '(?<![\w-])stat\s+-\w*c(?![\w-])' },
        @{ Name = 'grep -P (BSD grep has no PCRE)'; Pattern = '(?<![\w-])grep\s+(-\w+\s+)*-\w*P(?![\w-])' },
        @{ Name = 'date -d (GNU only)'; Pattern = '(?<![\w-])date\s+(-d(?![\w-])|--date)' },
        @{ Name = 'find -printf (GNU only)'; Pattern = '(?<![\w-])-printf(?![\w-])' },
        @{ Name = 'base64 -w (BSD base64 has no -w)'; Pattern = '(?<![\w-])base64\s+-\w*w' },
        # BSD sed reads the next word as the backup suffix, so `sed -i 's/a/b/'` eats the script.
        @{ Name = "sed -i with no backup argument (BSD needs one)"; Pattern = "(?<![\w-])sed\s+-i(?!\s*(''|`"`"|\.))" },
        @{ Name = 'mapfile/readarray (bash 4+)'; Pattern = '(?<![\w-])(mapfile|readarray)(?![\w-])' },
        @{ Name = 'declare -A (bash 4+)'; Pattern = '(?<![\w-])declare\s+-\w*A(?![\w-])' },
        @{ Name = 'case-modifying expansion (bash 4+)'; Pattern = '\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,)' },
        @{ Name = 'globstar **/ (bash 4+)'; Pattern = '(?<![\w*./])\*\*/' }
    )
    $hits = @()
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    $n = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $n++
        if ($line.TrimStart().StartsWith('#')) { continue }
        foreach ($rule in $rules) {
            if ($line -match $rule.Pattern) { $hits += "line ${n}: $($rule.Name)" }
        }
    }
    return @($hits)
}

function Get-PackSectionBody {
    <#
    .SYNOPSIS
      The text between a markdown heading and the next terminator. Empty when the heading is absent.
    .DESCRIPTION
      Five scripts each carried a byte-identical private copy of this (WQ-444), which is how a single
      defect took five patches in 2.22.73: the start-header search was unanchored, so it matched a
      heading *quoted inside a table cell*, began the Done section in the middle of the Active table,
      and reported every Active id as both active and done. Anchoring is therefore not a detail here -
      it is the whole reason the function exists in one place.
    .PARAMETER EndHeader
      Terminators. The literal '---' means a horizontal rule on its own line, not a heading.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$StartHeader,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$EndHeader
    )
    if ([string]::IsNullOrEmpty($Content)) { return '' }
    $m0 = [regex]::Match($Content, '(?m)^\s*' + [regex]::Escape($StartHeader))
    if (-not $m0.Success) { return '' }
    $slice = $Content.Substring($m0.Index + $StartHeader.Length)
    $endPos = $slice.Length
    foreach ($eh in $EndHeader) {
        if ($eh -eq '---') {
            $m = [regex]::Match($slice, '(?m)^\s*---\s*$')
        } else {
            $m = [regex]::Match($slice, '(?m)^\s*' + [regex]::Escape($eh))
        }
        if ($m.Success -and $m.Index -lt $endPos) { $endPos = $m.Index }
    }
    return $slice.Substring(0, $endPos)
}

function Get-PackVerifyRoot {
    <#
    .SYNOPSIS
      The pack copies this machine is answerable for: the one under test, and the one installed here.
    .DESCRIPTION
      Pack discovery is deliberately broad - it has to find a pack from inside an unrelated project, so
      it looks in the profile, on the Desktop, and in the OneDrive Desktop. Verification then reused
      that same list and validated *every* copy it found, which is a different question with a
      different answer.

      WQ-463: a backup copy of the pack on a OneDrive Desktop was being audited alongside the checkout.
      A stale or half-synced backup failed the verify, the failure surfaced as "verify-audit-system.ps1
      failed against the starter pack itself" during a bootstrap check, and it was unactionable from
      there - nothing in the project being audited, or in the checkout being edited, could fix a folder
      the user keeps as a backup. It also came and went as OneDrive hydrated and re-synced files,
      which is what made it look intermittent.

      A backup is not a delivery. Only two copies are in scope: the source pack these scripts belong
      to, and the installed copy this machine actually reads from.
    .PARAMETER Candidate
      Discovered roots, in discovery order. Order is preserved for the ones kept.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Candidate,
        [AllowEmptyString()][string]$SourceRoot = '',
        [AllowEmptyString()][string]$InstalledRoot = ''
    )
    $norm = {
        param($p)
        if ([string]::IsNullOrWhiteSpace($p)) { return '' }
        return ($p.Trim().TrimEnd('\', '/').ToLowerInvariant() -replace '/', '\')
    }
    $wanted = @(@($SourceRoot, $InstalledRoot) | ForEach-Object { & $norm $_ } | Where-Object { $_ })
    if ($wanted.Count -eq 0) { return @() }
    $kept = @()
    $seen = @()
    foreach ($c in $Candidate) {
        $k = & $norm $c
        if (-not $k) { continue }
        if ($wanted -notcontains $k) { continue }
        if ($seen -contains $k) { continue }
        $seen += $k
        $kept += $c
    }
    return @($kept)
}

function Get-PackChildFailureDetail {
    <#
    .SYNOPSIS
      The reason a child script failed, as a phrase to append to a Fix line. Empty when it succeeded.
    .DESCRIPTION
      A parent that reports "the child failed" and discards what the child said leaves nothing to
      diagnose from. WQ-463 is the case: an intermittent bootstrap failure inside the behavior suite
      reported only that a verify "failed", and the child's console output had already been swallowed
      by the harness, so four full audit runs produced no reason at all.

      An exit code with no [FAIL] line is reported as such rather than as success, because a child that
      fails silently is a worse defect than one that explains itself, and an empty detail would read as
      "nothing to say" instead of "it would not say".
    .PARAMETER MaxLines
      Cap on quoted lines, so one broken child cannot bury the rest of the report. Truncation is stated.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Output,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [int]$MaxLines = 6
    )
    if ($ExitCode -eq 0) { return '' }
    $marked = @()
    if (-not [string]::IsNullOrWhiteSpace($Output)) {
        $marked = @($Output -split "`r?`n" |
                Where-Object { $_ -match '^\s*\[(FAIL|WARN|ERROR)\]' } |
                ForEach-Object { $_.Trim() })
    }
    if ($marked.Count -eq 0) {
        return " - the child printed no [FAIL] line; exit code was $ExitCode"
    }
    $shown = @($marked | Select-Object -First $MaxLines)
    $detail = ' - reported: ' + ($shown -join ' | ')
    $hidden = $marked.Count - $shown.Count
    if ($hidden -gt 0) { $detail += " (+$hidden more)" }
    return $detail
}

function Get-PackStrayFailureLine {
    <#
    .SYNOPSIS
      The [FAIL] lines a child printed while still succeeding. Empty when it failed, or said nothing.
    .DESCRIPTION
      `[FAIL]` is this pack's word for "a check found something", and a reader - human or agent - is
      entitled to treat one as real. WQ-472 is what happens when they cannot: the behavior suite runs
      several child verifies against deliberately broken fixtures and requires them to fail, and one
      of those arms discarded the child's output with an error-only redirect, which cannot touch
      Write-Host. The finding printed to the host anyway, the parent audit quoted it into its Fix line
      (correctly - see Get-PackChildFailureDetail), and the certification run reported a SESSION path
      that exists in no file in the checkout. It cost a full diagnosis pass: the file was clean, the
      child verify exited 0 against it, and the suite itself reported zero failures.

      So the invariant is not about any one arm: **a run that succeeded must not have printed a
      marked failure line.** Checked by the parent, which is the only place that can see both the
      child's exit code and everything it wrote, and kept here as a function so the suite can exercise
      it on fixtures rather than infer it from reading the caller.

      Only [FAIL] counts. [WARN] and [SKIP] are things a passing run is expected to say.
    .PARAMETER Output
      The child's captured output - one string or an array of lines. Empty lines are legal input; a
      parameter that rejected them would report every clean run as silent (the WQ-433 lesson).
    #>
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )
    if ($ExitCode -ne 0) { return @() }
    if ($null -eq $Output) { return @() }
    $stray = @()
    foreach ($chunk in $Output) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        foreach ($line in ($chunk -split "`r?`n")) {
            if ($line -match '^\s*\[FAIL\]') { $stray += $line.Trim() }
        }
    }
    return @($stray)
}

function Test-PackSubstitutionMarker {
    <#.SYNOPSIS True when a string carries a substitution marker: <you>, {{ROOT}}, %LOCALAPPDATA%, $env:X.#>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '[<>{}%]') -or ($Value -match '\$env:')
}

function Test-PackRootAnchoredPath {
    <#
    .SYNOPSIS
      True when a path is anchored at *some* root - a real one or a placeholder for one.
    .DESCRIPTION
      Used where a bare relative path is the defect, because it opens whichever workspace happens to be
      current. A placeholder root counts: a handoff written for another machine cannot name a path that
      exists here, and hard-coding the sending machine's path is the disclosure that machine-local
      classification exists to prevent.
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = $Path.Trim()
    if ($p -match '^[A-Za-z]:\\') { return $true }
    if ($p -match '^/') { return $true }
    if ($p -match '^(<[^>]+>|%[^%]+%|\{\{[^}]+\}\}|\$env:[A-Za-z_][A-Za-z0-9_]*)[\\/]') { return $true }
    return $false
}

function Get-PackMachinePathHit {
    <#
    .SYNOPSIS
      Absolute paths in text that name a real machine. Empty result means the text is safe to travel.
    .PARAMETER Policy
      Strict       - any absolute path is a hit (files that travel: session notes, handoff packets).
      Illustrative - example paths are allowed (general docs, which need *a* concrete path to show).
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [ValidateSet('Strict', 'Illustrative')][string]$Policy = 'Strict'
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $hits = @()
    foreach ($m in [regex]::Matches($Text, $script:PackAbsolutePathPattern)) {
        $hit = $m.Groups[1].Value
        # A path built out of a marker is a template, not a location.
        if (Test-PackSubstitutionMarker $hit) { continue }
        if ($Policy -eq 'Illustrative') {
            $lower = $hit.ToLowerInvariant()
            $isExample = $false
            foreach ($marker in $script:PackIllustrationMarkers) {
                if ($lower.Contains($marker.ToLowerInvariant())) { $isExample = $true; break }
            }
            if (-not $isExample) {
                foreach ($who in $script:PackIllustrationUserNames) {
                    if ($lower -match ('[\\/]' + [regex]::Escape($who.ToLowerInvariant()) + '([\\/]|$)')) {
                        $isExample = $true; break
                    }
                }
            }
            if ($isExample) { continue }
        }
        $hits += $hit
    }
    return @($hits | Select-Object -Unique)
}
