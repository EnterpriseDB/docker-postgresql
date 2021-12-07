# Notes on IronBank

## Ironbank version of docker-postgresql in EDB repo

The CNP Docker image code is in the [`docker-postgresql`](https://github.com/EnterpriseDB/docker-postgresql/) repo.

It has a few amendments, specifically to comply with the set of dependencies
that the IronBank maintainers require.
Two relevant files: `generate_hardening_manifest.py` and `hardening_manifest.yaml.template`
 - The requirments.txt that is generated can't have annotations from pip-compile
 - The program 'generate_hardening_manifest.py' is provided by them \
	to automatically update resources in their env
 - The Base images get overridden by the IronBank build server so the build args 
	are necessary in Dockerfile


This has IronBank specific changes in order to meet their requirements.
See [docs/ subdirectory](docs/ironbank.md) for further detail.

## Updating IronBank after updates 
The update.sh script in IronBank/ creates all the artifacts required to create a docker-postgres container suitable for use in IronBank
It follows the same structure and steps from UBI and Debian version with some added steps for automatically generating Ironbank's files
As per usual in the `docker-postgresql` repo, the GH workflows have an `Automatic Updates`
workfow, and a `Continuous Integration`. The former is where the python script is run
and where the versions and substitutions for the template are computed.

After update.sh is run the contents of the directory should be copied over to the repo1.dso.mil repository and pushed. 
It is a manual step now; essentially ```cp -ar 12/* ~/<repo path>/repo1.dso.mil/dsop/enterprisedb/docker-postgresql/```

## Getting access to the Iron Bank repo

The Ironbank images are developed and stored in a gitlab repo.
You should get acces to it, at:
https://repo1.dso.mil/users/sign_in

You should enable 2FA on it (use your authenticator - 1Password wors fine)

The entry point for the Ironbank Containers is https://repo1.dso.mil/dsop
You should click the `Request Access` link -- though it doesn't seem a hard requirement.

After your account is ready ensure you are a member of this group:
[`enterprisedb`](https://repo1.dso.mil/dsop?filter=enterprisedb)

## Working on the repo
The model is that external parties (we) create a branch, and ask them, the
Ironbank admins, to merge.  They will do so into the branch `development`, and
possibly, from there onto `master`.

As part of the CI/CD run, a battery of scans is run, and a report is produced.
We should be ready to respond to it with explanations, when particular dependencies are
signaled by the scans.

### Important documentation
https://repo1.dso.mil/dsop/dccscr/-/blob/master/Hardening/
https://repo1.dso.mil/dsop/dccscr/-/blob/master/hardening%20manifest/README.md
https://repo1.dso.mil/dsop/dccscr/-/tree/master/pre-approval

### Justifications
https://repo1.dso.mil/dsop/dccscr/-/blob/master/pre-approval/justifications.md
Watch the video on this page.

