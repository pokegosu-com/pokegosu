// service <api url> — stands in for the one job a deployment's root has that
// the CLI needs: saying what the deployment is made of. Prints the port it
// took, and names itself as where a person would go to approve.
import { createServer } from 'node:http'

const apiURL = process.argv[2]

const server = createServer((req, res) => {
  if (req.url === '/.well-known/pokegosu.json') {
    const { port } = server.address()
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ api_url: apiURL, account_url: `http://127.0.0.1:${port}` }))
    return
  }
  res.statusCode = 404
  res.end()
})

// Written, not logged: console.log colours a number when FORCE_COLOR is set.
server.listen(0, '127.0.0.1', () => process.stdout.write(`${server.address().port}\n`))
