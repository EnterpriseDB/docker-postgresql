
# Major implementation details 
Have to use their base images. They use a hardened image.
  [see the Dockerfile requirements:](https://repo1.dso.mil/dsop/dccscr/-/blob/master/Hardening/Dockerfile_Requirements.md#requirements)
  - No labels in the Dockerfile, imported from manifest

Have to use their manifest file to specify which files to download. See [hardening manifest](https://repo1.dso.mil/dsop/dccscr/-/tree/master/hardening%20manifest).
  - They download and scan each file. Then copy them to an "enclave" system. 
  - The build service pulls them from the enclave for the Dockerfile

Have to be responsive to their alerts. 
  - They require a response within 24 hours
  - They require valid email contacts; no group accounts


# Overview
IronBank is a DoD organization that provides secure and hardened containers.
EDB is using IronBank as a vehicle to sell EDB products and services to govt. customers.


## Tools provided.
There is a sample python script that updates to the hardening manifest.
See [`resource_scripts`](https://repo1.dso.mil/dsop/container-hardening-tools/proof-of-concept/resource_scripts/)
