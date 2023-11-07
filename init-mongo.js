rs.initiate(
  {
    _id : "rs0",
    members: [
      { _id : 0, host : "mongo1:27011" },
      { _id : 1, host : "mongo2:27012" },
      { _id : 2, host : "mongo3:27013" }
    ]
  }
) 
