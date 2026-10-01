# RelayChat

RelayChat is an offline mesh communication application that uses Bluetooth Low Energy (BLE) to talk to ESP32 nodes, which then relay messages over long-range LoRa (SX1278).

## Current Status (Prototype)
> [!WARNING]
> **This is currently a prototype.** Payloads are transmitted in **plaintext** over the air, and identities are currently unauthenticated. Do not use this for sensitive communications yet. End-to-end encryption and persistent public/private key identities are planned for a future release.

## Features
- **Offline Mesh**: Messages bounce through ESP32 LoRa nodes to reach their destination.
- **Robust Framing**: Uses a custom length-prefixed binary protocol that gracefully handles BLE MTU fragmentation and LoRa packet size limits.
- **Auto-Discovery**: Periodically broadcasts presence to build a dynamic "Nearby Contacts" list.
- **Voice Messages**: Supports highly compressed Push-to-Talk voice chunks over LoRa.
- **Deduplication**: Mesh nodes track a ring-buffer of message IDs to drop infinite loops instantly.
