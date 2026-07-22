# Stub MQTT — alias legacy pour l'état hybride (phase 2)

Après migration du broker vers `smart-home`, ce Service redirige
`mosquitto.mosquitto.svc.cluster.local:1883` vers le broker réel.

**Ne pas supprimer** tant que frigate, zigbee2mqtt ou homeassistant
référencent encore `mosquitto.mosquitto` dans leur config.

Voir `docs/runbooks/mosquitto-phase2-ns-migration.md` pour la procédure d'exécution.
