#!/bin/zsh
# Build and run Dreamer in the simulator.
#   ./run.sh                          # iPhone 17, normal start
#   ./run.sh screen:journal           # open a screen directly (debug builds)
#   ./run.sh device:"iPhone 17 Pro" reset:true
#   ./run.sh test                     # unit tests
set -e
cd "${0:A:h}"
bundle check >/dev/null 2>&1 || bundle install
if [[ "$1" == "test" ]]; then
  shift
  exec bundle exec fastlane test "$@"
fi
exec bundle exec fastlane sim "$@"
