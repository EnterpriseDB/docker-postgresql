## Ironbank version of docker-postgresl

Contains the base files for creating the IronBank versions.

This has IronBank specific changes in order to meet their requirements.
See [docs/ subdirectory](docs/ironbank.md) for further detail.

Noteably: 
 - The requirments.txt that is generated can't have annotations from pip-compile
 - The program 'generate_hardening_manifest.py' is provided by them \
	to automatically update resources in their env
 - The Base images get overridden by the IronBank build server so the build args 
	are necessary in Dockerfile



The output of the update.sh script in IronBank/12 should be copied over to the IronBank repo and pushed. 
It is a manual step now; essentially ```cp -ar 12/* ~/<repo path>/repo1.dso.mil/dsop/enterprisedb/docker-postgresql/```




# Notes on IronBank

## EDB repo

The CNP Docker image code is in the [`docker-postgresql`](https://github.com/EnterpriseDB/docker-postgresql/) repo.

It has a few amendments, specifically to comply with the reduced set of dependencies
that the IronBank maintainers allow.
Two relevant files: `generate_hardening_manifest.py` and `hardening_manifest.yaml.template`

As per usual in the `docker-postgresql` repo, the GH workflows have an `Automatic Updates`
workfow, and a `Continuous Integration`. The former is where the python script is run
and where the versions and substitutions for the template are computed.

## Getting access to the Iron Bank repo

The Ironbank images are developed and stored in a gitlab repo.
You should get acces to it, at:
https://repo1.dso.mil/users/sign_in

You should enable 2FA on it (use your authenticator - 1Password wors fine)

The entry point for the Ironbank Containers is https://repo1.dso.mil/dsop
You should click the `Request Access` link -- though it doesn't seem a hard requirement.

Inside this repo there are two subgroups that are of interest to us:

1. [`enterprisedb`](https://repo1.dso.mil/dsop?filter=enterprisedb)
  at the moment it contains two folders. `cloud-native-postgresql` is still in flux and lots TBD
  as of early December, 2021.
  `docker-postgres` 
2. [`Opensource`](https://repo1.dso.mil/dsop/opensource) - this seems to be where we
  would want our postgresql images to live, eventually.
  There is a `postgres` subfolder there with versions 10, 11, 12 and 96 [sic]

## Working on the repo

The model seems to be that external parties (we) create a branch, and ask them, the
Ironbank admins, to merge.  They will do so into the branch `development`, and
possibly, from there onto `master`.

At the moment, in the `docker-postgres` folder, we have the `dev/initial` branch active
and some executions of the CI/CD pipeline.

[screengrab]

As part of the CI/CD run, a battery of scans is run, and a report is produced.
We should be ready to respond to it with explanations, when particular dependencies are
signaled by the scans.

[screengrab]
