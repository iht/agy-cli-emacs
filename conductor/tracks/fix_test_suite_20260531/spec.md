# Specification: Fix test suite environment setup and mock transient module dependencies in batch mode

## 1. Problem Description
Running the automated test suite `antigravity-cli-ide-tests.el` in Emacs batch mode (`emacs -batch -L . -l ert -l antigravity-cli-ide-tests.el -f ert-run-tests-batch-and-exit`) fails due to a missing dependency/function in the `transient` package:
```elisp
Symbol’s function definition is void: transient--set-layout
```
This is because `antigravity-cli-ide-transient.el` requires the `transient` library (loaded via `(require 'transient)`), but in batch mode, Emacs might load an older built-in version of `transient` which lacks the internal `transient--set-layout` function or layout definitions.

## 2. Proposed Changes
To ensure tests run successfully in batch mode and are fully sandboxed/stable:
1. **Mock modern `transient` dependencies**: Modify `antigravity-cli-ide-tests.el` to safely mock or stub `transient--set-layout` and any other missing transient functions/variables during ERT testing if they are not already defined.
2. **Ensure Clean Mocking**: Mocking should be localized to the testing session (batch/ERT) so it doesn't affect active interactive users.
3. **Verify Passing Tests**: Confirm that the ERT test suite runs cleanly and all 5 existing tests pass in batch mode.

## 3. Acceptance Criteria
- Running `emacs -batch -L . -l ert -l antigravity-cli-ide-tests.el -f ert-run-tests-batch-and-exit` completes with exit code 0.
- All five existing tests pass.
- No interactive behavior or production files are corrupted.
