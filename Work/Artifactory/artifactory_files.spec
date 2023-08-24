{
"files": [
  {
    "aql": {
      "items.find": {
        "repo": {"$eq":"cdo-docker"},
        "path": {"$match":"cdo/cannonball/build/"},
	      "type": {"$eq":"file"},
        "created": { "$before":"1d" }
      }
    }
  }
]
}
