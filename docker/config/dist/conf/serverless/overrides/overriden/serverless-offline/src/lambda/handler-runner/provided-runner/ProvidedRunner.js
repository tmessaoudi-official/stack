import { EOL } from "node:os"
import { relative } from "node:path"
import { cwd } from "node:process"
import { execa } from "execa"
import { log } from "../../../utils/log.js"

const { parse, stringify } = JSON
const { hasOwn } = Object

export default class ProvidedRunner {
  static #payloadIdentifier = "__offline_payload__"

  #env = null

  #handler = null

  constructor(funOptions, env) {
    this.#handler = funOptions.handler
    this.#env = env
  }

  // no-op
  // () => void
  cleanup() {}

  #parsePayload(value) {
    let payload

    for (const item of value.split(EOL)) {
      let json

      // first check if it's JSON
      try {
        json = parse(item)
        // nope, it's not JSON
      } catch {
        // no-op
      }

      // now let's see if we have a property __offline_payload__
      if (
        json &&
        typeof json === "object" &&
        hasOwn(json, ProvidedRunner.#payloadIdentifier)
      ) {
        payload = json[ProvidedRunner.#payloadIdentifier]
        // everything else is print(), logging, ...
      } else {
        log.notice(item)
      }
    }

    return payload
  }

  // invokeLocalPhp, loosely based on:
  // https://github.com/serverless/serverless/blob/v1.50.0/lib/plugins/aws/invokeLocal/index.js#L556
  // invoke.php, copy/pasted entirely as is:
  // https://github.com/serverless/serverless/blob/v1.50.0/lib/plugins/aws/invokeLocal/invoke.rb
  async run(event, context) {
    const runtime = platform() === "win32" ? "" : "sh"

    if ("" == runtime) {
      throw new Error("Runtime not available on this platform")
    }
    // https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

    // https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    // exclude callbackWaitsForEmptyEventLoop, don't mutate context
    const { callbackWaitsForEmptyEventLoop, ..._context } = context

    const input = stringify({
      context: _context,
      event,
    })

    // console.log(input)

    const { stderr, stdout } = await execa(
      `sh ${relative(cwd(), this.#handler)}`,
      {
        env: this.#env,
        input,
        shell: true,
      },
    )

    if (stderr) {
      // TODO

      log.notice(stderr)
    }

    return this.#parsePayload(stdout)
  }
}
