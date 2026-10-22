import { Plugin } from "@opencode/plugin"

/**
 * Prefix every session title with the date the session was created.
 *
 * OpenCode names a session from a model summary of the first exchange, so the
 * title alone carries no time information. A date prefix makes the session
 * list sortable by when the work started, which matters once a project has
 * several sessions in a day.
 *
 * The date comes from the session's creation time rather than the moment the
 * title was written, so the prefix stays stable when a session is renamed
 * later.
 *
 * Two events are handled:
 * - `session.created` covers sessions created with an explicit title.
 * - `session.renamed` covers auto-generated titles and manual renames.
 *
 * Titles that already begin with a date are left alone. That covers titles
 * written by hand in an `MM-DD` or `YYYY-MM-DD` style, and the plugin's own
 * updates, so it never re-prefixes a title it has already touched.
 */

/** A leading date, in either `YYYY-MM-DD` or `MM-DD` form. */
const DATE_PREFIXED = /^\d{4}-\d{2}-\d{2}\b|^\d{1,2}[-/]\d{1,2}\b/

function datePrefix(created: number): string {
	const date = new Date(created)
	const month = `${date.getMonth() + 1}`.padStart(2, "0")
	const day = `${date.getDate()}`.padStart(2, "0")
	return `${date.getFullYear()}-${month}-${day}`
}

/** Compare directories without tripping over a trailing slash. */
function sameDirectory(left: string | undefined, right: string | undefined): boolean {
	if (!left || !right) return false
	return left.replace(/\/+$/, "") === right.replace(/\/+$/, "")
}

export default Plugin.define({
	id: "opencode.session-title-date",
	async setup(ctx) {
		const controller = new AbortController()

		async function applyDate(sessionID: string, title: string | undefined) {
			if (!title || DATE_PREFIXED.test(title)) return

			try {
				const session = await ctx.session.get({ sessionID })
				const created = session.time?.created
				if (typeof created !== "number") return

				const updated = `${datePrefix(created)} - ${title}`
				if (session.title === updated) return

				await ctx.session.update({ sessionID, title: updated })
			} catch (error) {
				console.error(`session-title-date: could not date "${title}":`, error)
			}
		}

		void (async () => {
			for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
				if (event.type !== "session.created" && event.type !== "session.renamed") continue

				// A plugin instance is loaded per location and every instance sees
				// the whole event stream. Only the instance that owns the
				// session's location acts on it, so one session is not renamed
				// once per open location.
				const location = (event as { location?: { directory?: string } }).location
				if (!sameDirectory(location?.directory, ctx.location.directory)) continue

				const data = event.data as { sessionID?: string; title?: string } | undefined
				if (!data?.sessionID) continue

				await applyDate(data.sessionID, data.title)
			}
		})()

		return () => controller.abort()
	},
})
