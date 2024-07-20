#!/bin/bash
# adduser template

#if not exists:
#groupadd --gid 2000 backupusers
adduser --uid ${UID} --gid 2000 --disabled-password --disabled-login ${username}
# TODO: find non-interactive version.