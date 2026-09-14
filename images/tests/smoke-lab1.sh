#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
images_dir=$(dirname "$script_dir")
toolbox_image=${TOOLBOX_IMAGE:-gns3-lab/toolbox:lab1-smoke}

IMAGE_TAG="$toolbox_image" "$images_dir/toolbox/tests/smoke.sh"

run_variant() {
    test_script=$1
    TOOLBOX_IMAGE="$toolbox_image" SKIP_TOOLBOX_BUILD=1 "$test_script"
}

run_variant "$images_dir/Application/web-server/stages/lab1/vulnerable/tests/smoke.sh"
run_variant "$images_dir/Application/web-server/stages/lab1/complete/tests/smoke.sh"
run_variant "$images_dir/Application/dns-server/stages/lab1/no-recursion/tests/smoke.sh"
run_variant "$images_dir/Application/dns-server/stages/lab1/complete/tests/smoke.sh"
run_variant "$images_dir/Application/client/stages/lab1/no-cache/tests/smoke.sh"
run_variant "$images_dir/Application/client/stages/lab1/complete/tests/smoke.sh"

printf '%s\n' 'PASS: all lab 1 image smoke tests'