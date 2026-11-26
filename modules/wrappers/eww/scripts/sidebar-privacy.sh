#!/usr/bin/env bash

# Prints SHR while a PipeWire video input stream runs, which is how screen sharing shows up.

pw-dump 2>/dev/null | jq -c '
    [ .[]
      | select(.type == "PipeWire:Interface:Node")
      | select(.info.props["media.class"] == "Stream/Input/Video")
      | select(.info.state == "running")
      | .info.props["application.name"] // .info.props["node.name"] // "unknown" ]
    | if length == 0
      then {text: "", tooltip: "", class: ""}
      else {text: "SHR", tooltip: ("Sharing: " + join(", ")), class: "sharing"}
      end' || jq -nc '{text: "", tooltip: "", class: ""}'
