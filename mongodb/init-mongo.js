rs.initiate(
  {
    _id : "rs0",
    members: [
      { _id : 0, host : "host.docker.internal:27011" },
      { _id : 1, host : "host.docker.internal:27012" },
      { _id : 2, host : "host.docker.internal:27013" }
    ]
  }
) 
