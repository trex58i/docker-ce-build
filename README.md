# This branch is for chaining Prow jobs

The only purpose of this job is for triggering the execution of a prow job from another job.
We are using this for spliting up large prow job into smaller jobs so that a single job does not take an excessive 
execution time (Best practice would be no more than 2h) and causes any contention for the execution of the other pending
jobs.

## How this branch was created?
This branch was created as an orphan branch with no source code compared to the main branch.

```bash
 git checkout --orphan prow-job-tracking
 git rm --cached -r .
 ```
## How does it work?
When a job A want to trigger the execution of the job B, job A commit a file change in
this special tracking branch.
Job B need to be defined as a post-submit job that whatch for changes on the file that job A is changing.
The commit on that file trigger the execution of job B.
## How are those files organized?
Currently we have Docker build and Istio CI jobs using this trick.
Under the job directory you will find a directory by use case and the triggering file will be named the same as the prow job that does the git commit:
-istio/postsubmit-istio-build-job
-docker/postsubmit-build-docker
