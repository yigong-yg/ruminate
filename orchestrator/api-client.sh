#!/bin/bash
# Alma REST API client wrapper
# Usage: source this file, then call functions

ALMA_BASE_URL="${ALMA_BASE_URL:-http://localhost:23001}"

alma_get()    { curl -s "${ALMA_BASE_URL}${1}"; }
alma_post()   { curl -s -X POST "${ALMA_BASE_URL}${1}" -H "Content-Type: application/json" -d "${2}"; }
alma_put()    { curl -s -X PUT "${ALMA_BASE_URL}${1}" -H "Content-Type: application/json" -d "${2}"; }
alma_delete() { curl -s -X DELETE "${ALMA_BASE_URL}${1}"; }

# Memory operations
alma_memory_list()   { alma_get "/api/memories"; }
alma_memory_add()    { alma_post "/api/memories" "{\"content\":\"$1\",\"metadata\":$2}"; }
alma_memory_search() { alma_post "/api/memories/search" "{\"query\":\"$1\"}"; }
alma_memory_status() { alma_get "/api/memories/status"; }
alma_memory_stats()  { alma_get "/api/memories/stats"; }
alma_memory_rebuild(){ alma_post "/api/memories/rebuild" "{}"; }
alma_memory_embedding_model() { alma_get "/api/memories/embedding-model"; }

# Provider operations
alma_providers()     { alma_get "/api/providers"; }
alma_settings()      { alma_get "/api/settings"; }
