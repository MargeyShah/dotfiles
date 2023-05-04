{
"files": [
  {
    "aql": {
      "items.find": {
        "repo": {"$eq":"cdo-docker-local"},
        "path": {"$match":"cnbl-bundle/*"},
        "name": {"$eq":"manifest.json"},
        "created": { "$before":"30d" },
	      "stat.downloaded": { "$before":"30d"}
      }
    }
  }
]
}