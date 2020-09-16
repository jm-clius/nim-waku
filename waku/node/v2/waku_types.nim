## Core Waku data types are defined here to avoid recursive dependencies.
##
## TODO Move more common data types here

import
  std/tables,
  chronos,
  libp2p/[switch, peerinfo, multiaddress, crypto/crypto],
  libp2p/protobuf/minprotobuf,
  libp2p/protocols/pubsub/[pubsub, floodsub, gossipsub]

# Common data types -----------------------------------------------------------

type
  Topic* = string
  Message* = seq[byte]

  # TODO: these filter structures can be simplified but like this for now to
  # match Node API
  # Also, should reuse in filter/wakufilter code, but cyclic imports right now.
  ContentFilter* = object
    topics*: seq[string]

  ContentFilterHandler* = proc(message: seq[byte]) {.gcsafe, closure.}

  Filter* = object
    contentFilter*: ContentFilter
    handler*: ContentFilterHandler

  Filters* = Table[string, Filter]

  # NOTE based on Eth2Node in NBC eth2_network.nim
  WakuNode* = ref object of RootObj
    switch*: Switch
    wakuRelay*: WakuRelay
    peerInfo*: PeerInfo
    libp2pTransportLoops*: seq[Future[void]]
  # TODO Revist messages field indexing as well as if this should be Message or WakuMessage
    messages*: seq[(Topic, WakuMessage)]
    filters*: Filters

  WakuMessage* = object
    payload*: seq[byte]
    contentTopic*: string

  WakuRelay* = ref object of GossipSub
    gossipEnabled*: bool

# Encoding and decoding -------------------------------------------------------

proc init*(T: type WakuMessage, buffer: seq[byte]): ProtoResult[T] =
  var msg = WakuMessage()
  let pb = initProtoBuffer(buffer)

  discard ? pb.getField(1, msg.payload)
  discard ? pb.getField(2, msg.contentTopic)

  ok(msg)

proc encode*(message: WakuMessage): ProtoBuffer =
  result = initProtoBuffer()

  result.write(1, message.payload)
  result.write(2, message.contentTopic)

proc notify*(filters: Filters, msg: WakuMessage) =
  for filter in filters.values:
    # TODO: In case of no topics we should either trigger here for all messages,
    # or we should not allow such filter to exist in the first place.
    if filter.contentFilter.topics.len > 0:
      if msg.contentTopic in filter.contentFilter.topics:
        filter.handler(msg.payload)
