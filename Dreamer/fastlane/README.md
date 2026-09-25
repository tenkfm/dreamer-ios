fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios sim

```sh
[bundle exec] fastlane ios sim
```

Build the app and run it in the simulator

Options: device (simulator name), screen (debug start screen, e.g. journal), reset (true = clean install),

configuration (Debug, Staging or Release)

### ios test

```sh
[bundle exec] fastlane ios test
```

Run the unit tests in the simulator

Options: device (simulator name)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
