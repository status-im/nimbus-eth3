# beacon_chain
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

import
  std/[json, strutils],
  ../consensus_spec/os_ops

const
  Eth3Version* = "v0.4.1"
  Eth3FixturesDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / ".." / ".." / "vendor" / "nim-eth3-scenarios"
  Eth3TestsDir* = Eth3FixturesDir / ("tests-" & Eth3Version)

proc relativeEth3Path*(path: string, suitePath = Eth3TestsDir): string =
  try:
    path.relativePath(suitePath)
  except Exception as exc:
    raiseAssert "relativePath failed unexpectedly: " & exc.msg

proc parseEth3Json*(path: string): JsonNode =
  try:
    parseJson(os_ops.readFile(path))
  except CatchableError as err:
    writeStackTrace()
    try:
      stderr.write "JSON load issue for file \"", path, "\"\n"
      stderr.write err.msg, "\n"
    except IOError:
      discard
    quit 1

iterator walkEth3Fixtures*(dir: string): string {.raises: [OSError].} =
  for path in walkDirRec(dir):
    if path.endsWith(".json"):
      yield path

proc extractSingleFixtureCase*(doc: JsonNode): tuple[name: string, data: JsonNode] =
  doAssert doc.kind == JObject, "Expected top-level fixture JSON object"
  doAssert doc.len == 1, "Expected exactly one case per fixture file"

  for name, data in doc.pairs():
    return (name, data)

  raiseAssert "Expected exactly one case per fixture file"
