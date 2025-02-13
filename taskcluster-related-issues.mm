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
	562[562: <a href='https://github.com/mozilla/firefox-translations-training/issues/562'>oom looks like a preemption</a>]
	711[711: <a href='https://github.com/mozilla/firefox-translations-training/issues/711'>can't restart to run distillation</a>]
	719[719: <a href='https://github.com/mozilla/firefox-translations-training/issues/719'>improve usability of running selected tasks</a><br>status: ready to work on]
	728[728: <a href='https://github.com/mozilla/firefox-translations-training/issues/728'>start_stage often reruns evaluate tasks</a><br>status: translations eng should work on it<br>assigned: no]
	466[466: <a href='https://github.com/mozilla/firefox-translations-training/issues/466'>automatically upload artifacts</a>]
	375[375: <a href='https://github.com/mozilla/firefox-translations-training/issues/375'>switch away from level 1 workers</a><br>status: ready to work on<br>assigned: no]
	618[618: <a href='https://github.com/mozilla/firefox-translations-training/issues/618'>bring snakepit machines online</a>]
	700[700: <a href='https://github.com/mozilla/firefox-translations-training/issues/700'>use generic worker multiengine on gpu workers</a><br>status: waiting on chain of trust fix<br>assigned: bhearsum]
	391[391: <a href='https://github.com/mozilla/firefox-translations-training/issues/391'>docker for all tasks</a>]
	250[250: <a href='https://github.com/mozilla/firefox-translations-training/issues/250'>cancel all action doesn't work</a><br>status: ]
	tc6894[tc6894: <a href='https://github.com/taskcluster/taskcluster/issues/6894'>generic worker should handle OOM better</a><br>status: needs tc team help<br>assigned: no]
	tc6951[tc6951: <a href='https://github.com/taskcluster/taskcluster/issues/6951'>action tasks fire against incorrect group sometimes</a><br>status: ready to work on<br>assigned: no]
	549[549: <a href='https://github.com/mozilla/firefox-translations-training/issues/549'>dns resolution issues</a><br>status: waiting to see if new images fix it<br>assigned: bhearsum]
	tc7014[tc7014: <a href='https://github.com/taskcluster/taskcluster/issues/7014'>imageArtifactHash does not exist in g-w/d2g</a><br>status: waiting for tc to fix it]
	relops1307[relops1307: <a href='https://mozilla-hub.atlassian.net/browse/RELOPS-1307'>reimage snakepit machines</a><br>status: in progress<br>assigned: aerickson/yarik]

	tc6894 --> 562
	719 --> 711
	710 --> 466
	391 --> 618
	700 --> 391
	tc6951 --> 250
	700 --> 710
	710 --> 375
	relops1307 --> 618
	tc7014 --> 700
