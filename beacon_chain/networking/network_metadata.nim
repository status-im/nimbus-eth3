# beacon_chain
# Copyright (c) 2018-2025 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [], gcsafe.}

import
  std/os,
  stew/byteutils, stew/shims/macros,
  chronicles,
  eth/common/eth_types_json_serialization,
  ../spec/[eth2_ssz_serialization, forks]

from std/sequtils import deduplicate, filterIt, mapIt
from std/strutils import
  endsWith, escape, parseBiggestUInt, replace, splitLines, startsWith, strip,
  toLowerAscii

# TODO(zah):
# We can compress the embedded states with snappy before embedding them here.

# ATTENTION! This file is intentionally avoiding the Nim `/` operator for
# constructing paths. The standard operator is relying the `DirSep` constant
# which depends on the selected target OS (when doing cross-compilation), so
# the compile-time manipulation of paths performed here will break (e.g. when
# cross-compiling for Windows from Linux)
#
# Nim seems to need a more general solution for detecting the host OS during
# compilation, so a host OS specific separator can be used when deriving paths
# from `currentSourcePath`.

export RuntimeConfig

const
  vendorDir = currentSourcePath.parentDir.replace('\\', '/') & "/../../vendor"

  incbinEnabled* = sizeof(pointer) == 8

type
  Eth1Network* = enum
    mainnet

  GenesisMetadataKind* = enum
    NoGenesis
    UserSuppliedFile
    BakedIn
    BakedInUrl

  DownloadInfo* = object
    url: string
    digest: Eth2Digest

  GenesisMetadata* = object
    case kind*: GenesisMetadataKind
    of NoGenesis:
      discard
    of UserSuppliedFile:
      path*: string
    of BakedIn:
      networkName*: string
    of BakedInUrl:
      url*: string
      digest*: Eth2Digest

  Eth2NetworkMetadata* = object
    # If the eth1Network is specified, the ELManager will perform some
    # additional checks to ensure we are connecting to a web3 provider
    # serving data for the same network. The value can be set to `None`
    # for custom networks and testing purposes.
    eth1Network*: Opt[Eth1Network]
    cfg*: RuntimeConfig

    # Parsing `enr.Records` is still not possible at compile-time
    bootstrapNodes*: seq[string]

    genesis*: GenesisMetadata

func hasGenesis*(metadata: Eth2NetworkMetadata): bool =
  metadata.genesis.kind != NoGenesis

proc readBootstrapNodes(path: string): seq[string] {.raises: [IOError].} =
  # Read a list of ENR values from a YAML file containing a flat list of entries
  var res: seq[string]
  if fileExists(path):
    for line in splitLines(readFile(path)):
      let line = line.strip()
      if line.startsWith("enr:"):
        res.add line
      elif line.len == 0 or line.startsWith("#"):
        discard
      else:
        when nimvm:
          raiseAssert "Bootstrap node invalid (" & path & "): " & line
        else:
          warn "Ignoring invalid bootstrap node", path, bootstrapNode = line
  res

proc readBootEnr(path: string): seq[string] {.raises: [IOError].} =
  # Read a list of ENR values from a YAML file containing a flat list of entries
  var res: seq[string]
  if fileExists(path):
    for line in splitLines(readFile(path)):
      let line = line.strip()
      if line.startsWith("- enr:"):
        res.add line[2 .. ^1]
      elif line.startsWith("- \"enr:") and line.endsWith("\""):
        res.add line[3 .. ^2]  # Gnosis Chiado `boot_enr.yaml`
      elif line.len == 0 or line.startsWith("#"):
        discard
      else:
        when nimvm:
          raiseAssert "Bootstrap ENR invalid (" & path & "): " & line
        else:
          warn "Ignoring invalid bootstrap ENR", path, bootstrapEnr = line
  res

proc loadEth2NetworkMetadata*(
    path: string,
    eth1Network = Opt.none(Eth1Network),
    isCompileTime = false,
    downloadGenesisFrom = Opt.none(DownloadInfo),
    useBakedInGenesis = Opt.none(string)
): Result[Eth2NetworkMetadata, string] {.raises: [IOError, PresetFileError].} =
  # Load data in mainnet format
  # https://github.com/eth-clients/mainnet

  try:
    let
      genesisPath = path & "/genesis.ssz"
      configPath = path & "/config.yaml"
      bootstrapNodesLegacyPath = path & "/bootstrap_nodes.txt"  # <= Dec 2024
      bootstrapNodesPath = path & "/bootstrap_nodes.yaml"
      bootEnrPath = path & "/boot_enr.yaml"
      runtimeConfig = if fileExists(configPath):
        let (cfg, unknowns) = readRuntimeConfig(configPath)
        if unknowns.len > 0:
          when nimvm:
            # TODO better printing
            echo "Unknown constants in file: " & unknowns
          else:
            warn "Unknown constants in config file", unknowns
        cfg
      else:
        defaultRuntimeConfig

      bootstrapNodes = deduplicate(
        readBootstrapNodes(bootstrapNodesLegacyPath) &
        readBootEnr(bootstrapNodesPath) &
        readBootEnr(bootEnrPath))

    ok Eth2NetworkMetadata(
      eth1Network: eth1Network,
      cfg: runtimeConfig,
      bootstrapNodes: bootstrapNodes,
      genesis:
        if downloadGenesisFrom.isSome:
          GenesisMetadata(kind: BakedInUrl,
                          url: downloadGenesisFrom.get.url,
                          digest: downloadGenesisFrom.get.digest)
        elif useBakedInGenesis.isSome:
          GenesisMetadata(kind: BakedIn, networkName: useBakedInGenesis.get)
        elif fileExists(genesisPath) and not isCompileTime:
          GenesisMetadata(kind: UserSuppliedFile, path: genesisPath)
        else:
          GenesisMetadata(kind: NoGenesis))

  except PresetIncompatibleError as err:
    err err.msg

  except ValueError as err:
    raise (ref PresetFileError)(msg: err.msg)

proc loadCompileTimeNetworkMetadata(
    path: string,
    eth1Network = Opt.none(Eth1Network),
    useBakedInGenesis = Opt.none(string),
    downloadGenesisFrom = Opt.none(DownloadInfo)): Eth2NetworkMetadata =
  if fileExists(path & "/config.yaml"):
    try:
      let res = loadEth2NetworkMetadata(
        path, eth1Network, isCompileTime = true,
        downloadGenesisFrom = downloadGenesisFrom,
        useBakedInGenesis = useBakedInGenesis)
      if res.isErr:
        macros.error "The current build is misconfigured. " &
                     "Attempt to load an incompatible network metadata: " &
                     res.error
      return res.get
    except IOError as err:
      macros.error "Failed to load network metadata at '" & path & "': " &
                   "IOError - " & err.msg
    except PresetFileError as err:
      macros.error "Failed to load network metadata at '" & path & "': " &
                   "PresetFileError - " & err.msg
  else:
    macros.error "config.yaml not found for network '" & path

when IsMainnetSupported:
  when incbinEnabled:
    # Nim is very inefficent at loading large constants from binary files so we
    # use this trick instead which saves significant amounts of compile time
    {.push hint[GlobalVar]:off.}
    let
      mainnetGenesisVar {.importc: "eth2_mainnet_genesis".}: ptr UncheckedArray[byte]
      mainnetGenesisSizeVar {.importc: "eth2_mainnet_genesis_size".}: int
    {.pop.}

    template mainnetGenesis*(): ptr UncheckedArray[byte] = {.noSideEffect.}: mainnetGenesisVar
    template mainnetGenesisSize*: int = {.noSideEffect.}: mainnetGenesisSizeVar

    # let `.incbin` in assembly file find the binary file through search path
    {.passc: "-I" & escape(vendorDir).}
    {.compile: "network_metadata_mainnet.S".}

  else:
    const
      mainnetGenesis* = slurp(
        vendorDir & "/mainnet/metadata/genesis.ssz")

  const
    mainnetMetadata = loadCompileTimeNetworkMetadata(
      vendorDir & "/mainnet/metadata",
      Opt.some mainnet,
      useBakedInGenesis = Opt.some "mainnet")

  static:
    doAssert ConsensusFork.high == ConsensusFork.Gloas
    for network in [mainnetMetadata]:
      checkForkConsistency(network.cfg)
      doAssert network.cfg.FULU_FORK_EPOCH < FAR_FUTURE_EPOCH
      doAssert network.cfg.GLOAS_FORK_EPOCH == FAR_FUTURE_EPOCH
      doAssert network.cfg.BLOB_SCHEDULE.len == 2

proc getMetadataForNetwork*(networkName: string): Eth2NetworkMetadata =
  template loadRuntimeMetadata(): auto =
    if fileExists(networkName / "config.yaml"):
      try:
        let res = loadEth2NetworkMetadata(networkName)
        res.valueOr:
          fatal "The selected network is not compatible with the current build",
            reason = res.error
          quit 1
      except IOError as exc:
        fatal "Cannot load network: IOError", msg = exc.msg, networkName
        quit 1
      except PresetFileError as exc:
        fatal "Cannot load network: PresetFileError", msg = exc.msg, networkName
        quit 1
    else:
      fatal "config.yaml not found for network", networkName
      quit 1

  let metadata =
    when IsMainnetSupported:
      case toLowerAscii(networkName)
      of "mainnet":
        mainnetMetadata
      else:
        loadRuntimeMetadata()
    else:
      loadRuntimeMetadata()

  metadata

proc getRuntimeConfig*(eth2Network: Option[string]): RuntimeConfig =
  ## Returns the run-time config for a network specified on the command line
  ## If the network is not explicitly specified, the function will act as the
  ## regular Nimbus binary, returning the mainnet config.
  ##
  ## TODO the assumption that the input variable is a CLI config option is not
  ## quite appropriate in such as low-level function. The "assume mainnet by
  ## default" behavior is something that should be handled closer to the `conf`
  ## layer.
  let metadata =
    if eth2Network.isSome:
      getMetadataForNetwork(eth2Network.get)
    else:
      when IsMainnetSupported:
        mainnetMetadata
      else:
        # This is a non-standard build (i.e. minimal), and the function was
        # most likely executed in a test. The best we can do is return a fully
        # default config:
        return defaultRuntimeConfig

  metadata.cfg

when IsMainnetSupported:
  template bakedInGenesisStateAsBytes(networkName: untyped): untyped =
    when incbinEnabled:
      `networkName Genesis`.toOpenArray(0, `networkName GenesisSize` - 1)
    else:
      `networkName Genesis`.toOpenArrayByte(0, `networkName Genesis`.high)

  const
    availableOnlyInMainnetBuild =
      "Baked-in genesis states for the official Ethereum " &
      "networks are available only in the mainnet build of Nimbus"

  template bakedBytes*(metadata: GenesisMetadata): auto =
    case metadata.networkName
    of "mainnet":
      when IsMainnetSupported:
        bakedInGenesisStateAsBytes mainnet
      else:
        raiseAssert availableOnlyInMainnetBuild
    else:
      raiseAssert "The baked network metadata should use one of the name above"

  func bakedGenesisValidatorsRoot*(metadata: Eth2NetworkMetadata): Opt[Eth2Digest] =
    case metadata.genesis.kind
    of BakedIn:
      try:
        let header = SSZ.decode(
          toOpenArray(metadata.genesis.bakedBytes, 0, sizeof(BeaconStateHeader) - 1),
          BeaconStateHeader)
        Opt.some header.genesis_validators_root
      except SerializationError:
        raiseAssert "Invalid baken-in genesis state"
    else:
      Opt.none Eth2Digest
else:
  func bakedBytes*(metadata: GenesisMetadata): seq[byte] =
    raiseAssert "Baked genesis states are not available in the current build mode"

  func bakedGenesisValidatorsRoot*(metadata: Eth2NetworkMetadata): Opt[Eth2Digest] =
    Opt.none Eth2Digest
