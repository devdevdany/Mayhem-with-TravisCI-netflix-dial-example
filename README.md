# Getting Started

To get started with this example, you will need to fork this repository and complete the following process in Travis CI:

> **Note:** You will also need to create a `mayhem` organization in the Mayhem UI prior to executing the pipeline, as the [run-mayhem.sh](mayhem/scripts/run-mayhem.sh) script uses a Mayhem Organization as the target run namespace.

## Travis CI Setup

1. Go to the [Travis CI](https://www.travis-ci.com/) website and sign up or log into an existing account. Make sure that your GitHub account has been linked to your Travis CI account.
2. Within the Travis CI dashboard, you should now see your forked repository as well as the two branches: `master` and `CVE-2019-10028-FIX`.
3. Within the forked GitHub repo, navigate to the [.travis.yml](.travis.yml) file and set the following environment variables for your `master` and `CVE-2019-10028-FIX` branches. These credentials will be used to authenticate with the Mayhem instance and push the corresponding netflix Docker target.

    ```yaml
    # Additional environment values - either specify here or in your
    # Travis-CI job configuration.
    - MAYHEM_URL=https://my-company.forallsecure.com
    - DOCKER_REGISTRY=my-company.forallsecure.com:5000
    - IMAGE_TAG=my-company.forallsecure.com:5000/mayhem-netflix-dial-reference:${TRAVIS_BRANCH}
    - MAYHEM_TOKEN="AT1.abcdefg"
    ```

## Execute Continuous Fuzzing

For Continuous Fuzzing, Mayhem will fuzz the latest version of your software residing on the primary (master) branch, and by default, set Continuous Fuzzing runs with an infinite duration—only stopping a current Mayhem run and beginning a new Mayhem run when a new commit has been pushed to the primary branch. Thus, the name "Continuous Fuzzing".

1. Navigate to your forked repository in Travis CI and click on *More options* > *Trigger build*. Execute a new pipeline for the `master` branch.
2. The new pipeline for the `master` branch should now build the netflix Docker target and upload the corresponding Docker image to the specified Mayhem instance. A new Mayhem run for the bugged `dial-reference-master` target will then execute and find the underlying defects.

## Execute Regression Testing

For Regression Testing, Mayhem will execute regression tests on new changes or code using previously generated crashing test cases found during Continuous Fuzzing to determine if known defects have been fixed.

1. Navigate to your forked repository in Travis CI and click on *More options* > *Trigger build*. Execute a new pipeline for the `CVE-2019-10028-FIX` branch.
2. The new pipeline for the `CVE-2019-10028-FIX` branch should now build the netflix Docker target and upload the corresponding Docker image to the specified Mayhem instance with the same test corpus generated from the `dial-reference-master` target. A Mayhem run for the fixed `dial-reference-cve-2019-10028-fix` target will then execute to ensure that defects have been resolved.

# Mayhem Example (dial-reference)

[![Build Status](https://travis-ci.org/ForAllSecure/Mayhem-with-TravisCI-netflix-dial-example.svg?branch=master)](https://travis-ci.org/ForAllSecure/Mayhem-with-TravisCI-netflix-dial-example)

This repository has been forked from the official [dial-reference repository](https://github.com/Netflix/dial-reference)
repository in GitHub. Additional content has been added to serve as a reference
architecture on how to integrate [ForAllSecure](https://forallsecure.com) Mayhem
into a continuous integration / continuous deployment (CI/CD) workflow.

This example provides the necessary configuration files, pipeline scripts and
documentation necessary to execute a fuzzing test run using [Travis CI](https://travis-ci.org/)].
In order to leverage this example, the user is expected to have access
to their own Mayhem instance.

This example has been tested with Mayhem 1.3.0+.

Original [dial-reference README](README.md.orig)

## Why dial-reference?

In 2019 [ForAllSecure](https://forallsecure.com) discovered [CVE-2019-10028](https://nvd.nist.gov/vuln/detail/CVE-2019-10028),
a denial of service bug caused by an out of bounds write in a Netflix Dial
protocol reference server ([CVSS Score](https://nvd.nist.gov/vuln-metrics/cvss): 7.5).

 We reported this bug responsibly to the maintainers, with the fix implemented
 [here](https://github.com/Netflix/dial-reference/commit/bfde1461449f6c0dfde3d2a826b97cace325cc75).

This fork of dial-reference demonstrates how Mayhem can discover the issue, as well as
how the regression-testing capabilities of Mayhem can be used to verify the fix
in a separate branch.

## CI/CD with Travis CI

This repository demonstrates how to use [Travis CI](https://travis-ci.org) to:

* Build dial-reference and continuously fuzz the output to always be looking for new
  issues.
* Run regression tests generated from continuous fuzzing against a branch.

## What is being fuzzed

The build will create the `dial-reference/server` binary and copy it into a Docker image that
will be uploaded to Mayhem for fuzzing using network fuzzing.

## Defining the Mayhem Run

A Mayhem "Target" is defined using a `Mayhemfile`. A `Mayhemfile` is included
under [mayhem/Mayhemfile](mayhem/Mayhemfile). It is recommended to inspect the
comments and properties of this file to understand how the project will be named
inside of Mayhem.

The `cmds` property of the [Mayhemfile](mayhem/Mayhemfile) describes how the
`server` is started, as well as how Mayhem will interact with it over tcp:

```yaml
cmds:
  - cmd: /dial-reference/server/dialserver
    dictionary: /http.dict
    env:
      LD_LIBRARY_PATH: /dial-reference/server

    network:
      url: tcp://localhost:56790 # protocol, host and port to analyze
      is_client: false           # target is a client-side program
      timeout: 2.0               # max seconds for sending data
```

## Travis CI

This example makes use of [Travis CI](https://travis-ci.org)
to coordinate the build and Mayhem integration. There is nothing in the build
flow that requires Travis CI. The same concepts can be applied to different build
tools.

The [.travis.yml](.travis.yml) file is located in the root of the project and defines
the build that will run Mayhem. The bulk of the work to run Mayhem and
to differentiate between continuous and regression runs is in
[run-mayhem.sh](mayhem/scripts/run-mayhem.sh). This script downloads the
`mayhem` cli, which is used to initiate runs.
