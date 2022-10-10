#!/bin/bash

for ((i=1;i<=100;i++)); 
do 
   # your-unix-command-here
   VAR=$(($i * 100))
   [ $TEE == 200 ] && echo $VAR
   
done