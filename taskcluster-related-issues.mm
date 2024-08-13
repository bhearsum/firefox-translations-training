---
title: Taskcluster related issues and relationships between them - remove issues entirely as they are fixed
---
%% Everything Taskcluster related from
%% https://github.com/mozilla/firefox-translations-training/issues/490
%% and https://github.com/mozilla/firefox-translations-training/issues/311
%% should be included here
%% remove items as they are fixed. anything with no arrows pointing to it
%% is ready to be worked on

flowchart LR
	710[710: <a href='https://github.com/mozilla/firefox-translations-training/issues/710'>switch to generic worker for all tasks</a>]
	653[653: <a href='https://github.com/mozilla/firefox-translations-training/issues/653'>task has too many dependencies</a>]
	538[538: <a href='https://github.com/mozilla/firefox-translations-training/issues/538'>cache issues on d2g tasks</a>]
	630[630: <a href='https://github.com/mozilla/firefox-translations-training/issues/630'>random errors on d2g tasks</a><br>status: waiting on new worker image]
	628[628: <a href='https://github.com/mozilla/firefox-translations-training/issues/628'>eval fails or pretrained backwards model</a><br>status: waiting on review<br>assigned: bhearsum]
	562[562: <a href='https://github.com/mozilla/firefox-translations-training/issues/562'>oom looks like a preemption</a>]
	711[711: <a href='https://github.com/mozilla/firefox-translations-training/issues/711'>can't restart to run distillation</a>]
	719[719: <a href='https://github.com/mozilla/firefox-translations-training/issues/719'>improve usability of running selected tasks</a><br>status: discuss at all hands]
	728[728: <a href='https://github.com/mozilla/firefox-translations-training/issues/728'>start_stage often reruns evaluate tasks</a><br>status: waiting on translations eng input<br>assigned: no]
	466[466: <a href='https://github.com/mozilla/firefox-translations-training/issues/466'>automatically upload artifacts</a>]
	375[375: <a href='https://github.com/mozilla/firefox-translations-training/issues/375'>switch away from level 1 workers</a><br>status: ready to work on<br>assigned: no]
	618[618: <a href='https://github.com/mozilla/firefox-translations-training/issues/618'>bring snakepit machines online</a>]
	700[700: <a href='https://github.com/mozilla/firefox-translations-training/issues/700'>use generic worker multiengine on cpu workers</a><br>status: waiting on new worker image<br>assigned: bhearsum]
	391[391: <a href='https://github.com/mozilla/firefox-translations-training/issues/391'>docker for all tasks</a>]
	250[250: <a href='https://github.com/mozilla/firefox-translations-training/issues/250'>cancel all action doesn't work</a><br>status: ]
	tc7151[tc7151: <a href='https://github.com/taskcluster/taskcluster/issues/7151'>increase task dependency limit</a><br>status: waiting for testing + release with increased limit<br>assigned: yarik]
	tc7128[tc7128: <a href='https://github.com/taskcluster/taskcluster/issues/7128'>generic worker breaks cached files</a><br>status: half fixed; other half needs more investigation<br>assigned: bhearsum/pmoore]
	tc6894[tc6894: <a href='https://github.com/taskcluster/taskcluster/issues/6894'>generic worker should handle OOM better</a><br>status: needs tc team help<br>assigned: no]
	tc6951[tc6951: <a href='https://github.com/taskcluster/taskcluster/issues/6951'>action tasks fire against incorrect group sometimes</a><br>status: ready to work on<br>assigned: no]
	tc4595[tc4595: <a href='https://github.com/taskcluster/taskcluster/issues/4595'>support headless mode in generic-worker multiuser</a><br>status: being worked on<br>assigned: pmoore]
	new-cpu-image[build an updated version of the cpu worker image]
	new-gpu-image[build an updated version of the gpu worker image]

	630 --> 710
	538 --> 710
	tc7151 --> 653
	tc7128 --> 538
	tc6894 --> 562
	719 --> 711
	710 --> 466
	391 --> 618
	700 --> 391
	tc6951 --> 250
	tc4595 --> new-gpu-image
	new-gpu-image --> 700
	tc7128 --> new-cpu-image
	700 --> 710
	new-cpu-image --> 710
	710 --> 391
	new-cpu-image --> 630
