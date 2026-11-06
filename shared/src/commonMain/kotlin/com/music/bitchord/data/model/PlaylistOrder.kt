// Playlist drag-reorder model; computes minimal move set for YouTube's ACTION_MOVE_VIDEO_BEFORE API.
package com.music.bitchord.data.model

/**
 * One step of a playlist reorder: put the entry [setVideoId] directly before
 * [before], or at the very end of the playlist when [before] is null.
 *
 * Expressed in set-video-ids rather than positions because that is the only
 * shape YouTube's `ACTION_MOVE_VIDEO_BEFORE` takes, and because a position
 * means nothing once the first move has shifted everything after it.
 */
data class PlaylistMove(val setVideoId: String, val before: String?)

/**
 * The moves that turn the playlist [current] into [target], both given as
 * set-video-ids, fewest first.
 *
 * Only the entries outside the longest run already in the right relative order
 * move at all, so dragging one track to a new spot is one request entry however
 * far it went — not one per row it passed. The rest are placed walking [target]
 * from its end, each directly before the entry that should follow it, which by
 * then is already where it belongs.
 *
 * Empty when nothing changed, and when the two lists are not the same entries:
 * a playlist that gained or lost a row since [current] was read is not one this
 * can safely rearrange.
 */
fun playlistMoves(current: List<String>, target: List<String>): List<PlaylistMove> {
    if (current == target) return emptyList()
    if (current.size != target.size ||
        current.toSet() != target.toSet() ||
        current.toSet().size != current.size
    ) {
        return emptyList()
    }
    val position = current.withIndex().associate { (index, id) -> id to index }
    val stay = longestIncreasingRun(target.map { position.getValue(it) })
        .mapTo(HashSet()) { target[it] }
    val moves = ArrayList<PlaylistMove>(target.size)
    for (index in target.indices.reversed()) {
        val id = target[index]
        if (id in stay) continue
        moves += PlaylistMove(id, target.getOrNull(index + 1))
    }
    return moves
}

/** Indices into [values] of one longest strictly increasing subsequence. */
private fun longestIncreasingRun(values: List<Int>): List<Int> {
    if (values.isEmpty()) return emptyList()
    val tails = mutableListOf<Int>()   // tails[i] = smallest tail of IS of length i+1
    val prev = IntArray(values.size) { -1 }
    val pos = IntArray(values.size)
    for (i in values.indices) {
        val v = values[i]
        var lo = 0
        var hi = tails.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (tails[mid] < v) lo = mid + 1 else hi = mid
        }
        pos[i] = lo
        if (lo == tails.size) tails.add(v) else tails[lo] = v
        prev[i] = if (lo > 0) {
            (0 until i).lastOrNull { pos[it] == lo - 1 && values[it] < v } ?: -1
        } else -1
    }
    // Reconstruct
    val result = mutableListOf<Int>()
    var idx = (0 until values.size).lastOrNull { pos[it] == tails.size - 1 } ?: return emptyList()
    while (idx >= 0) {
        result.add(idx)
        idx = prev[idx]
    }
    return result.reversed()
}
