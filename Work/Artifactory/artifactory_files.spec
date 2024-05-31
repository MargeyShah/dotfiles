{
"files": [
  {
    "aql": {
      "items.delete": {
        "repo": {"$eq":"customer-modeling-pypi-local"},
        "path": {"$eq":"featurama"},
        "name": {"$match": "*.gz"}, 
        "created": {"$lt": "2023-12-13T20:50:00Z"}
      }
    }
  }
]
}
