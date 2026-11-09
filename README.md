# ANNA

ANNA is a Godot-based personal assistant. Speech output prefers the configured
local-network Piper service and falls back to the operating system's installed
text-to-speech voices when Piper is unavailable. The assistant does not require
internet access for this speech fallback.

## Configure Piper

By default, ANNA uses `http://192.168.137.1:5000/synthesize`. To use another
Piper server, edit `anna_settings.cfg` in the Godot user data directory for
this project and set:

```ini
[speech]
piper_url="http://127.0.0.1:5000/synthesize"
```

The endpoint must be reachable on the local network. ANNA gives the Piper
availability check and synthesis requests a timeout; if a request fails or
returns an invalid audio response, the queued utterance is sent to local
system speech instead. If no compatible OS voice is installed, speech output
is unavailable, but typed assistant interaction remains available.
Say `status` to see the last-known internet and Piper/LAN service state and the
current local-first/offline mode. Piper is checked on startup; status reporting
does not initiate a network request.

## Feature learning

When ANNA recognizes an unsupported capability request, reply `Learn now`,
`Learn later`, or `Not now`. Learn now checks connectivity, fetches web search
results, and, when an OpenAI-compatible model is configured, sends the request
and excerpts to that model for a cited engineering proposal. If offline, reply
`Retry` or `Learn later`.
Requests are stored in `user://feature_learning_queue.json`; Learn later moves
the request to the end of the FIFO queue, and repeating a request promotes the
existing item instead of creating a duplicate. Say `Learn next` to review the
oldest deferred request; interrupted or failed requests are made available in
the queue after restart. Queue records include status, timestamps, and the OS
device identifier when available.

Research results and proposals are for review, not instructions to execute.
ANNA does not install generated code or alter device permissions or settings
as part of learning. Online research is only started after the user chooses
Learn now or Retry.

The shared service status distinguishes internet connectivity from configured
LAN services such as Piper. The internet probe is separate from the search
provider and is used only when research is explicitly started; set
`connectivity_endpoint` under `[research]` to a reachable HTTP(S) endpoint if
the default probe is unavailable. A failed connectivity check blocks web/model
requests but does not disable typed commands, local assistant features, or
local OS speech fallback. After a successful probe, if connectivity is no
longer confirmed before model summarization, ANNA saves the sources locally
without contacting the model.

## Daily journal

Type `journal` (or `open journal`) to open ANNA's text-first journal. It shows
a daily writing prompt, lets you save an entry, and displays the ten most
recent entries. Entries are stored locally in
`user://journal_entries.json`; journaling does not use internet access or send
entries to an online service. If the journal file cannot be read or written,
ANNA reports the problem and disables saving rather than silently claiming
success. After sign-in, ANNA opens the daily prompt once per local calendar day
when no journal entry for that day exists. The prompt date is saved alongside
the entries to avoid repeating on later launches that day; if local storage
cannot be read or updated, ANNA skips the automatic prompt. Voice notes, photo,
and video capture are not included; those require separate device capabilities
and will be considered later.

## Local activity and privacy

Type `activity log` to view recent activity, or use the **Clear activity log**
button and confirm to remove it. The append-only log is stored on this device
at `user://activity_log.json`. It records event timestamps and metadata for
research starts/completions, online model disclosure (provider host, model,
and source count), saved proposal ID, command names/outcomes, and
connectivity/Piper fallbacks. It does not record API keys, authorization
headers, journal contents, search excerpts, or full request text. If the file
is malformed or cannot be read/written, ANNA reports the error and stops
logging rather than overwriting unknown data; clearing malformed data requires
using the explicit confirmed clear action.

## Multi-device registry (local foundation)

Type `device registry` or `manage devices` to maintain local device and feature
records in `user://device_registry.json`. The current platform scope is a PC
desktop hub and Android client; new device records are limited to those types.
Records capture a display name, device ID, recorded capabilities, and local
state; new records are marked **unpaired**. A confirmed revoke only changes
local state and clears hub-consent metadata for that record.
Feature records capture identity/version, device-exclusive or shareable scope,
compatible device types, required permissions, and testing/approval metadata.
Approval is descriptive metadata only; records do not install or enable
features.

### TLS pairing foundation

The desktop Godot app can act as the PC hub; the Android export is the only
supported client. Pairing controls are hidden on other platforms and transport
validation rejects non-Android clients. On the hub, keep the default
`127.0.0.1` bind for local testing, or enter the PC's private LAN IPv4 address.
Listening on all interfaces requires an additional confirmation; do not enable
router port forwarding. Firewall policy still determines reachability. Android
exports already request the `INTERNET` permission for this client transport.

Start the hub, copy its public TLS certificate to the Android client through a
trusted out-of-band channel, create a one-time invitation, and enter the hub's
LAN IPv4 address, port, invitation code, certificate, and client name on
Android. The invitation expires after two minutes and is consumed by a valid
request. The client must check its pairing-consent box, and the hub user must
approve the displayed client. The client persists a pending local record; the
hub saves its paired state only after the client confirms that storage; the
client then marks its record paired after receiving the final response. A
connection lost during that final response can leave the hub paired record
without a completed client record; check/revoke the hub record before retrying.
The hub's private TLS key stays in `user://anna_hub_private.key`; the public
certificate is stored in `user://anna_hub.crt`. These files rely on the local
OS account's user-data-directory protections and are not encrypted by ANNA.
Never share the private key.

The client saves its stable random device ID in `user://anna_device_id.txt` and
the pinned hub address/certificate in `user://anna_paired_hub.json`. Use
**Forget saved hub on this device** to remove only that client-side record;
revoke the client separately in the hub registry. Pairing is only an
authenticated enrollment handshake. It does not keep a session open, sync
conversations, exchange capability consent, invoke features, or control
appliances. Declared capabilities are metadata; no capability permission is
granted by pairing. Those require later, separately consented and enforced
protocol steps.

Static checks passed, but the scripts have not been parsed or exercised in the
Godot runtime in this environment. If the registry or TLS credential storage is
malformed or unavailable, pairing fails closed; interrupted pending records are
returned to the unpaired state on next load. This is a pairing foundation, not
production-ready device synchronization.

### Manual conversation handoff

Type `handoff` on either Godot app to prepare a package from the latest
conversation messages in memory. Review the export, confirm the checkbox, and
copy it through a channel you trust; on the receiving device paste the package,
review its contents, and separately confirm import. The package is limited to
40 recent user/assistant messages and 120 KB. It is not encrypted, signed, or
authenticated, and it is not sent over the pairing connection. Do not copy
sensitive conversations through an untrusted clipboard or messaging service.

Imported messages are appended as a single explicitly labeled, untrusted
context message; they do not execute commands or automatically trigger a model
response. They remain in memory only. On the next conversation request, this
context is included in the app's LAN model request. This is a manual
context-transfer workflow, not live synchronization or a resumable device
session.

### Capability request and household status metadata

Open `device registry`, `capability route`, `request capability`, or
`household status`. A capability route request names one capability, a
registered target device ID, and a short user intent. ANNA checks that the
device is active, advertises the capability or matches a feature record scoped
to that device/type, and that matching feature is tested and approved in its
metadata. It checks hub and client consent for the capability and each
feature-declared permission. Consent and approval are metadata only; this app
has no client-side per-capability approval exchange, so a client approval is
not inferred from pairing and route checks remain blocked unless explicit
client consent already exists. After confirmation that the intent text will be
stored locally, the result is saved in `user://device_registry.json` as
`not_sent` with the exact blocking reason. Because this app has no authenticated
live client session or execution protocol, requests are never delivered or
executed, even when registry metadata passes the checks. Approval metadata is
not authority to invoke a device function.

The household status section stores user-entered observations against an
optional local device record, with an observed timestamp. These values are
manual and not live readings. The status-request form can save a request for a
named household item and optional active device record, after confirmation, to
`household_status_requests` in the same local registry. Each record is
`not_sent` and includes why it cannot be routed: pairing is enrollment only,
and this app has neither a persistent authenticated client session nor an
appliance status adapter. It does not update the manual observation or query
any appliance. ANNA does not discover, query, or control appliances.
Appliance integrations and consequential action flows remain out of scope
until specific hardware/protocols and an independently consented, enforced
authorization flow are selected.

## Configure online research

The feature-learning component reads `anna_settings.cfg` from the Godot
user-data directory. A basic DuckDuckGo HTML search and OpenAI-compatible
model configuration looks like:

```ini
[research]
search_endpoint="https://html.duckduckgo.com/html/"
connectivity_endpoint="https://www.google.com/generate_204"
model_endpoint="https://api.example.com/v1/chat/completions"
model_name="your-model-name"
api_key_env_var="ANNA_MODEL_API_KEY"
```

The search endpoint must accept a `q` query parameter and return DuckDuckGo
HTML, DuckDuckGo Instant Answer JSON, or JSON with a `results` array containing
`title`, `snippet` (or `description`), and `url`. Model endpoints use the
OpenAI-compatible chat-completions request/response format. Use HTTPS for
remote model providers; HTTP is accepted only for localhost/127.0.0.1 model
servers. Do not put an API key in `anna_settings.cfg`: set the configured
environment variable before launching ANNA instead. Keys are not written to
the app config or proposal files. This project has no OS keychain integration;
if environment variables are unsuitable, secure credential storage needs a
separate platform-specific decision.

Search excerpts and the feature request are sent to the configured model
provider only after `Learn now`; without a model URL, model name, and key,
ANNA saves an auditable source-only summary instead. Proposals are saved under
`user://feature_proposals/` with the original request and source URLs.

The Vosk/GdVosk speech-recognition extension and model are optional and are not
included in this repository. No model or large dependency is downloaded
automatically.
