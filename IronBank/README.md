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
