#!/bin/bash
DIR=$PWD
CMD=$@

source $HOME/.bash_profile

cd $HOME/ProxyPass
java -jar ProxyPass.jar &
PID=$!

cd $DIR
$CMD

kill -1 $PID
