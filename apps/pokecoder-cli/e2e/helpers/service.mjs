// service <api url> — stands in for pokecoder-web's one job the CLI needs:
// saying where the API is. Prints the port it took.
import { createServer } from 'node:http'

const apiURL = process.argv[2]

const server = createServer((req, res) => {
  if (req.url === '/.well-known/pokecoder.json') {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ api_url: apiURL }))
    return
  }
  res.statusCode = 404
  res.end()
})

// Written, not logged: console.log colours a number when FORCE_COLOR is set.
server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`))
