#!/bin/bash

set -e

export VERSION=$(cat VERSION) 

./cmnode/bin/cmnode-${VERSION} foreground
