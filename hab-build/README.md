# hab-build

`hab-build` folder configuration contents are used by Jenkinsfile for automated builds of the `effortless` Chef Habitat artifacts

## Pre-Requisites & Components

* Contents for `hab-build` reside within the `effortless` repository which also contains the base Habitat plan configuration items.
Related tree contents:

        /repobase
        ├── Jenkinsfile_habbuild
        ├── hab-build/
        │   ├── README.md
        │   ├── hab-bootstrap.ps1
        │   └── hab-bootstrap.sh
        ├── habitat/
        ├── kitchen.habbuild.yml
        ├── kitchen.yml
        ├── results/

* Requires usage of AIG GitHub Enterprise server and Jenkins server with Pipeline workflow configurations enabled, along with kitchen-vcenter connectivity access and configuration.  Requirements of Jenkins server mirror `aig_hardening` cookbook.


## Usage

Usage of this hab-build module is specifically tied to `effortless` Habitat package creation as configured within local repository which maintains the `effortless` plan files.

* When used in coordination with Jenkins, this workflow will build a new version of the `effortless` Habitat package when there is a new successful `master` branch of `aig_hardening` cookbook completed along with an associated cookbook artifact deployment.
* The `aig_hardening` cookbook will have the following step contents in the `publish` stage of its `Jenkinsfile`, after the successful Artifactory publish:

        steps {
            ... (existing logic for publishing to Artifactory in publish stage)
            echo 'Build stage was successful so building a new Habitat package for effortless'
            // Call job effortless_habbuild to build, passing the version number of this artifact
            build job: 'effortless_habbuild', parameters: [ string(name: 'pkgversion', value: "${pkg_version}") ]
        }

* Jenkins job `effortless_habbuild` should be created pointing to the `effortless` repository and referencing to use configuration file `Jenkinsfile_habbuild`
* `effortless_habbuild` Jenkins job will not run a build unless it is invoked with parameter `pkgversion` -- this makes it so that the job will only run to create a new build with a targeted version number in plan files
* The `effortless_habbuild` does an in-place upgrade of the version number in the plan files while running the build, but this version number is not checked back in to the `effortless` repository.
