#!/bin/bash
DIR=$PWD
CMD=$@

cd $HOME/ProxyPass
java -jar ProxyPass.jar &
PID=$!

cd $DIR
$CMD

kill -1 $PID
