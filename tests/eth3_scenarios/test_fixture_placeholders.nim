# beacon_chain
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}
{.used.}

import
  std/[json, strutils],
  ../testutil,
  ../consensus_spec/os_ops,
  ./fixtures_utils

const
  ExpectedFixtureFormats = [
    "ssz",
    "state_transition_test",
    "fork_choice_test",
    "verify_signatures_test"
  ]

proc getRequiredObject(node: JsonNode, key, relativePath: string): JsonNode =
  doAssert node.kind == JObject, "Expected object fixture for " & relativePath
  result = node{key}
  doAssert not result.isNil, "Missing key \"" & key & "\" in " & relativePath
  doAssert result.kind == JObject,
    "Expected key \"" & key & "\" to contain an object in " & relativePath

proc getRequiredString(node: JsonNode, key, relativePath: string): string =
  doAssert node.kind == JObject, "Expected object fixture for " & relativePath
  let value = node{key}
  doAssert not value.isNil, "Missing key \"" & key & "\" in " & relativePath
  doAssert value.kind == JString,
    "Expected key \"" & key & "\" to contain a string in " & relativePath
  value.getStr()

proc expectedFixtureFormat(relativePath: string): string =
  let normalizedPath = relativePath.replace('\\', '/')

  if normalizedPath.contains("/ssz/"):
    "ssz"
  elif normalizedPath.contains("/state_transition/"):
    "state_transition_test"
  elif normalizedPath.contains("/fork_choice/"):
    "fork_choice_test"
  elif normalizedPath.contains("/verify_signatures/"):
    "verify_signatures_test"
  else:
    doAssert false, "Unsupported Eth3 fixture path: " & relativePath
    ""

proc runEth3PlaceholderTest(path: string) =
  let relativePath = relativeEth3Path(path)

  test "Eth3 - " & relativePath:
    let
      doc = parseEth3Json(path)
      (caseName, caseData) = extractSingleFixtureCase(doc)
      info = getRequiredObject(caseData, "_info", relativePath)
      description = getRequiredString(info, "description", relativePath)
      context =
        "Case: " & caseName & "\n" &
        "Description: " & description

    # Placeholder-only coverage: keep the fixture wired into the test suite
    # until semantic Eth3 execution is implemented.
    let
      network = getRequiredString(caseData, "network", relativePath)
      leanEnv = getRequiredString(caseData, "leanEnv", relativePath)
      fixtureFormat = getRequiredString(info, "fixtureFormat", relativePath)
      testId = getRequiredString(info, "testId", relativePath)
      normalizedPath = relativePath.replace('\\', '/')
      envDir = normalizedPath.split('/')[0]

    doAssert caseData.kind == JObject,
      "Expected fixture case to be an object in " & relativePath & "\n" & context
    doAssert network == "Devnet",
      "Unexpected network in " & relativePath & "\n" & context
    doAssert leanEnv == envDir,
      "Unexpected leanEnv in " & relativePath & "\n" & context
    doAssert fixtureFormat == expectedFixtureFormat(relativePath),
      "Unexpected fixtureFormat in " & relativePath & "\n" & context
    doAssert fixtureFormat in ExpectedFixtureFormats,
      "Unsupported fixtureFormat in " & relativePath & "\n" & context
    doAssert caseName.len > 0,
      "Expected non-empty case name in " & relativePath & "\n" & context
    doAssert testId.len > 0,
      "Expected non-empty testId in " & relativePath & "\n" & context
    doAssert description.len > 0,
      "Expected non-empty description in " & relativePath & "\n" & context

    let expectException = caseData{"expectException"}
    if not expectException.isNil:
      doAssert expectException.kind == JString,
        "Expected string expectException in " & relativePath & "\n" & context

    let expectExceptionMessage = caseData{"expectExceptionMessage"}
    if not expectExceptionMessage.isNil:
      doAssert expectExceptionMessage.kind == JString,
        "Expected string expectExceptionMessage in " & relativePath & "\n" & context

suite "Eth3 - Placeholder Vectors":
  doAssert dirExists(Eth3TestsDir),
    "You need to run the \"vendor/nim-eth3-scenarios/download_test_vectors.sh v0.4.1\" script to retrieve the Eth3 test vectors."

  for leanEnvDir in ["test", "prod"]:
    let baseDir = Eth3TestsDir / leanEnvDir
    doAssert dirExists(baseDir),
      "Missing Eth3 fixture directory: " & baseDir

    for path in walkEth3Fixtures(baseDir):
      runEth3PlaceholderTest(path)
