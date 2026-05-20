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

### ios beta

```sh
[bundle exec] fastlane ios beta
```



### ios setup_dev_certs

```sh
[bundle exec] fastlane ios setup_dev_certs
```

Install development certs & profiles (readonly)

### ios sync_profiles

```sh
[bundle exec] fastlane ios sync_profiles
```

ADMIN ONLY: sync profiles for newly added devices

### ios add_device

```sh
[bundle exec] fastlane ios add_device
```

ADMIN ONLY: add a single device then sync profiles

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
