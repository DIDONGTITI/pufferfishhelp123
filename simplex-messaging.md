# Simplex messaging protocol

A generic client-server protocol for asynchronous distributed unidirectional messaging

## Problems of the existing messaging protocols

- Identity related problems:
  - visibility of user contacts to anybody observing messages
  - unsolicited messages (spam and abuse)
  - trademark issues (when usernames are used)
  - privacy issues (when phone numbers are used)

  Participants' identities are known to the network. Depending on the identity type (e.g., phone number, DNS-based, username, uuid, public key, etc.) it creates different problems, but in all cases it exposes participants and their contacts graph to the network and also allows for unsolicited messages (spam and abuse).

- [MITM attack][1]. Any mechanism of the key exchange via the same network is prone to this type of attack when the public keys of the participants are substituted with the public keys of the attacker intercepting communication. While some solutions have been proposed that complicate MITM attack (social millionaire, OTR), if the attacker understands the protocol and has intercepted and can substitute all information exchanged between the participants, it is still possible to substitute encryption keys. It means that the existing [E2EE][2] implementations in messaging protocols and platforms can be compromised by the attacked who either compromised the server or communication channel.


## Simplex messaging protocol abstract

The proposed "simplex messaging protocol" removes the need for participants' identities and provides [E2EE][2] without the possibility of [MITM attack][1] attack under one assumption: participants have an existing alternative communication channel that they trust and can use to pass one small binary message to initiate the connection (out-of-band message).

The out-of band message is sent via some trusted alternative channel by the connection recipient to the connection sender. This message is used to share the encryption (a.k.a. "public") key and connection URI requried to establish a unidirectional (simplex) connection:
- the sender of the connection (who received out-of-band message) will use it to send messages to the server using connection URI, signing the message by sender key.
- the recepient of the connection (who created the connection and who sent out-of-band message) will use it to retrieve messages from the server, signing the requests by the recepient key.
- participant identities are not shared with the server, as completely new keys and connection URI are used for each connection.

This simplex connection is the main building block of the network that is used to build application level primitives (in graph-chat protocol) that are only known to system participants in their client applications (graph vertices) - user profiles, contacts, conversations, groups and broadcasts. At the same time, system servers are only aware of the low-level simplex connections. In this way a high level of privacy and security of the conversations is provided. Application level chat primitives defined in graph-chat protocol are not in scope of this simplex messaging protocol.

This approach is based on the concepts of [unidirectional networks][4] that are used for applications with high level of information security.

Defining the approach to out-of-band message passing is out of scope of this simplex messaging protocol. For practical purposes, and from the graph-chat client application point of view, various solutions can be used, e.g. one of the versions or the analogues of [QR code][3] (or their sequence) that is read via the camera, either directly from the chat participant's device or via the video call. Although a video call still allows for a highly sophisticated MITM attack, it requires that in addition to compromising simplex connection to intercept messages, the attacker also identifies and compromises the video connection in another channel and substitutes the video in real time - it seems extremely unlikely.


## Simplex connection - the main unit of protocol design

The network consists of multiple "simplex connections" (i.e. unidirectional, non-duplex). Access to each connection is controlled with unique (not shared with other connections) assymetric key pairs, separate for sender and the receiver. The sender and the receiver have private keys, and the server has associated public keys to verify participants.

The messages sent into the connection are encrypted and decrypted using another key pair - the recepient has the private key and the sender has the associated public key.

**Simplex connection diagram:**

![Simplex connection](/diagrams/simplex-messaging/simplex.svg)

Connection is defined by ID (`ID`) unique to the server, sender URI `SU` and receiver URI `RU`. Sender key (`SK`) is used by the server to verify sender's requests (made via `SU`) to send messages. Recipient key (`RK`) is used by the server to verify recipient's requests (made via `RU`) to retrieve messages.

The protocol uses different URIs for sender and recipient in order to provide an additional connection privacy by complicating correlation of senders and recipients.


## How Alice and Bob use simplex messaging protocol

Alice (recipient) wants to receive the messages from Bob (sender).

To do it Alice and Bob follow these steps:

1. Alice creates a simplex connection on the server:
   1. she decides which simplex messaging server to use (can be the same or different server that Alice uses for other connections).
   2. she generates a new random public/private key pair (encryption key - `EK`) that she did not use before for Bob to encrypt the messages.
   3. she generates another new random public/private key pair (recepient key - `RK`) that she did not use before for her to sign requests to retrieve the messages from the server.
   4. she generates a unique connection `ID` - generic simplex messaging protocol only requires that:
      - it is generated by the client.
      - it is unique on the server.
   5. she requests from the server to create a simplex connection. The request to create the connection is un-authenticated and anonymous. This connection definition contains previouisly generated connection `ID` and a uniqie "public" key `RK` that will be used to:
      - verify the requests to retrieve the messages as signed by the same person who created the connection.
      - update the connection, e.g. by setting the key required to send the messages (initially Alice creates the connection that accepts unsigned requests to send messages, so anybody could send the message via this connection if they knew the connection URI).
   6. The server responds with connection URIs:
      - recipient URI `RU` for Alice to retrieve messages from the connection.
      - sender URI `SU` for Bob to send messages to the connection.
2. Alice sends an out-of-band message to Bob via the alternative channel that both Alice and Bob trust (see [Simplex messaging protocol abstract](#simplex-messaging-protocol-abstract) above). The message includes:
   - the unique "public" key (`EK`) that Bob should use to encrypt messages.
   - the sender connection URI `SU` for Bob to use.
3. Bob, having received the out-of-band message from Alice, accepts the connection:
   1. he generates a new random public/private key pair (sender key - `SK`) that he did not use before for him to sign requests to Alice's server to send the messages.
   2. he prepares the first message for Alice to confirm the connection. This message includes:
      - previously generated "public" key `SK` that will be used by Alice's server to verify Bob's requests to send messages.
      - optionally, any information that allows Alice to identify Bob (e.g., in [graph-chat protocol][7] it is Bob's chat profile, but it can be any other information).
      - optionally, any other additional information (e.g., Bob could pass the details of another connection including sender connection URI and a new "public" encryption key for Alice to send reply messages to Bob, also see [graph-chat protocol][7]).
   3. he encrypts the message by the "public" key `EK` (that Alice provided via the out-of-band message).
   4. he sends the encrypted message to the connection URI `SU` to confirm the connection (that Alice provided via the out-of-band message). This request to send the first message does not need to be signed.
4. Alice retrieves Bob's message from the server via recipient connection URI `RU`:
   1. she decrypts retrieved message with "private" key `EK`.
   2. even though anybody could have sent the message to the connection `ID` before it is secured (e.g. if communication is compromised), Alice would ignore all messages until the decryption succeeds (i.e. the result contains the expected message structure). Optionally, she also may identify Bob using the information provided, but it is not required by this protocol.
5. Alice secures the connection `ID` so only Bob can send messages to it:
   1. she sends the request to `RU` signed with "private" key `RK` to update the connection to only accept requests signed by "private" key `SK` provided by Bob.
   2. From this moment the server will accept only signed requests, and only Bob will be able to send messages to the `SU` corresponding to connection `ID`.
6. The simplex connection `ID` is now established on the server.

**Creating simplex connection from Bob to Alice:**

![Creating connection](/diagrams/simplex-messaging/simplex-creating.svg)


Bob now can securely send messages to Alice.

1. Bob sends the message:
   1. he encrypts the message to Alice with "public" key `EK` (provided by Alice, only known to Alice and Bob, used only for one simplex connection).
   2. he signs the request to the server (via `SU`) using the "private" key `SK` (that only he knows, used only for this connection).
   3. he sends the request to the server, that the server will verify using the "public" key SK (that Alice provided to the server).
2. Alice retrieves the message(s):
   1. she signs request to the server with the "private" key `RK` (that only she has, used only for this connection).
   2. the server, having verified Alice's request with the "public" key `RK` that she provided, responds with Bob's message(s).
   3. she decrypts Bob's message(s) with the "private" key `EK` (that only she has).

**Sending messages from Bob to Alice via simplex connection:**

![Using connection](/diagrams/simplex-messaging/simplex-using.svg)


A higher level protocol (e.g., [graph-chat][7]) defines the semantics that allow to use two simplex connections (or two sets of connections for redundancy) for the bi-directional messaging chat and for any other communication scenarios.

The simplex messaging protocol is intentionally sipmlex - it provides no answer to how Bob will know that the process succeeded, and whether Alice received any messages. There may be a situation when Alice wants to securely receive the messages from Bob, but she does not want Bob to have any proof that she received any messages - this low-level simplex messaging protocol can be used in this scenario, as all Bob knows as a fact is that he was able to send one unsigned message to the server that Alice provided, and now can only send messages signed with the key `SK` that he sent to the server - it does not prove that any message was received by Alice.

For practical purposes of bi-directional conversation, now that Bob can securely send encrypted messages to Alice, Bob can establish the second simplex connection that will allow Alice to send messages to Bob in the same way. If both Alice and Bob have their respective uniqie "public" keys (Alice's and Bob's `EK`s of two separate connections), the conversation can be both encrypted and signed.

The established connection can also be used to change the encryption keys providing [forward secrecy][5].

This protocol also can be used for off-the-record messaging, as Alice and Bob can have multiple connections established between them and only information they pass to each other allows proving their identity, so if they want to share anything off-the-record they can initiate a new connection without linking it to any other information they exchanged. As a result, this protocol provides better anonymity and better protection from [MITM][1] than [OTR][6] protocol.

How simplex connections are used by the participants (graph vertices) is defined by graph-chat protocol and is not in scope of this low level simplex messaging protocol.


## Alternative flow to establish a simplex connection

When Alice and Bob already have a secure duplex (bi-directional) communication channel that allows to conveniently send two out-of-band messages, a flow with smaller number of steps to establish the connection can be used.

TODO

**Alternative flow of creating a simplex connection from Bob to Alice:**

![Alternative flow of creating connection](/diagrams/simplex-messaging/simplex-creating-alt.svg)


## Elements of the generic simplex messaging protocol

- defines only message-passing protocol:
  - transport agnostic - the  protocol does not define how clients connect to the servers and does not require persistent connections. While a generic term "request" is used, it can be implemented in various ways - HTTP requests, messages over (web)sockets, etc. This is defined by simplex messaging server protocol.
  - not semantic - the protocol does not assign any meaning to connections and messages. While on the application level the connections and messages can have different meaning (e.g., for messages: text or image chat message, message acknowledgement, participant profile information, status updates, changing "public" key to encrypt messages, changing servers, etc.), on the simplex messaging protocol level all the messages are binary and their meaning can only be interpreted by client applications and not by the servers - this interpretation is in scope of graph-chat protocol and out of scope of this simplex messaging protocol.
- client-server architecture:
  - multiple servers, that can be deployed by the system users, can be used to send and retrieve messages.
  - servers do not communicate with each other and do not even "know" about other servers.
  - clients only communicate with servers (excluding the initial out-of-band message), so the message passing is asynchronous.
  - for each connection, the message recipient defines the server through which the sender should send messages.
  - while multiple servers and multiple connections can be used to pass each chat message, it is in scope of graph-chat protocol, and out of scope of this simplex messaging protocol.
  - servers store messages only until they are retrieved by the recipients
  - servers are not supposed to store any message history or delivery log, but even if the server is compromised, it does not allow to decrypt the messages or to determine the list of connections established by any participant - this information is only stored on client devices.
- the only element provided by simplex messaging servers is simplex connections:
  - each connection is created and managed by the connection recipient.
  - assymetric encryption is used to sign and verify the requests to send and receive the messages.
  - one unique "public" key is used for the servers to authenticate requests to send the messages into the connection, and another unique "public" key - to retrieve the messages from the connection. "Unique" here means that each "public" key is used only for one connection and is not used for any other context - effectively this key is not public and does not represent any participant identity.
  - both "public" keys are provided to the server by the connection recepient when the connection is established.
  - the "public" keys known to the server and used to authenticate requests from the participants are unrelated to the keys used to encrypt and decrypt the messages - the latter keys are also unique per each connection but they are only known to participants, not to the servers.
  - messaging graph can be asymmetric: Bob's ability to send messages to Alice does not automatically lead to the Alice's ability to send messages to Bob.
  - connections are identified by the "connection URI" - server URI and connection ID (`ID`).


[1]: https://en.wikipedia.org/wiki/Man-in-the-middle_attack
[2]: https://en.wikipedia.org/wiki/End-to-end_encryption
[3]: https://en.wikipedia.org/wiki/QR_code
[4]: https://en.wikipedia.org/wiki/Unidirectional_network
[5]: https://en.wikipedia.org/wiki/Forward_secrecy
[6]: https://en.wikipedia.org/wiki/Off-the-Record_Messaging
[7]: graph-chat.md
