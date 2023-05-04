{
"files": [
  {
    "aql": {
      "items.find": {
        "repo": {"$eq":"hulu-docker"},
        "path": {"$match":"cdo-docker/cdo"},
        "name": {"$ne":"_uploads"},
	      "type": {"$eq":"folder"},
        "created": { "$before":"30d" },
	      "stat.downloaded": { "$before":"30d"}
      }
    }
  }
]
}
