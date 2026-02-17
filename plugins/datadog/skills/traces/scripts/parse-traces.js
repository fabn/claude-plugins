#!/usr/bin/env node

/**
 * Parse Datadog trace response and extract essential fields.
 *
 * Reduces 100KB+ trace responses to ~2KB of relevant data.
 *
 * Usage:
 *   echo '<raw_json>' | node parse-traces.js
 *   node parse-traces.js < trace-response.json
 *
 * Input: Raw JSON from mcp__datadog__list_traces
 * Output: Condensed JSON with trace summaries
 *
 * Supports two response formats:
 * 1. List format: { traces: [{ attributes: {...}, id, type }] }
 * 2. Spans format: { data: [{ spans: [...] }] } or { spans: [...] }
 */

const MAX_STACK_LINES = 10;

/**
 * Parse trace from list_traces API format (attributes structure)
 */
function parseListTrace(trace) {
  const attr = trace.attributes || {};
  const custom = attr.custom || {};
  const http = custom.http || {};
  const errorInfo = custom.error || {};
  const additionalProps = attr.additionalProperties || {};

  // Extract error information
  let error = null;
  if (additionalProps.status === 'error' || errorInfo.type) {
    const stack = errorInfo.stack || '';
    const stackLines = stack.split('\n').slice(0, MAX_STACK_LINES);

    error = {
      type: errorInfo.type || 'Unknown',
      message: errorInfo.message || 'No message',
      stack: stackLines.length > 0 && stackLines[0] ? stackLines.join('\n') : null
    };
  }

  // Build endpoint string
  const method = http.method || '';
  const path = http.url || http.path || '';
  const endpoint = method ? `${method} ${path}` : (path || attr.resourceName || '');

  // Duration in milliseconds (custom.duration is in nanoseconds)
  const durationNs = custom.duration || 0;
  const durationMs = Math.round(durationNs / 1000000);

  // HTTP status
  const httpStatus = http.status_code;

  // Trace ID
  const traceId = attr.traceId;

  // Timestamp
  const timestamp = attr.startTimestamp || null;

  return {
    traceId: String(traceId),
    status: additionalProps.status || 'ok',
    httpStatus: httpStatus ? Number(httpStatus) : null,
    endpoint,
    resource: attr.resourceName,
    service: attr.service,
    durationMs,
    timestamp,
    error,
    datadogUrl: `https://app.datadoghq.com/apm/trace/${traceId}`
  };
}

/**
 * Parse trace from spans format (used in single trace lookup)
 */
function parseSpansTrace(trace) {
  const spans = trace.spans || [];
  const rootSpan = spans.find(s => !s.parent_id) || spans[0] || {};
  const meta = rootSpan.meta || {};
  const metrics = rootSpan.metrics || {};

  // Extract error information
  let error = null;
  if (rootSpan.error === 1 || meta['error.type']) {
    const stack = meta['error.stack'] || '';
    const stackLines = stack.split('\n').slice(0, MAX_STACK_LINES);

    error = {
      type: meta['error.type'] || 'Unknown',
      message: meta['error.msg'] || meta['error.message'] || 'No message',
      stack: stackLines.length > 0 && stackLines[0] ? stackLines.join('\n') : null
    };
  }

  // Build endpoint string
  const method = meta['http.method'] || '';
  const path = meta['http.url'] || meta['http.route'] || rootSpan.resource || '';
  const endpoint = method ? `${method} ${path}` : path;

  // Duration in milliseconds
  const durationNs = rootSpan.duration || 0;
  const durationMs = Math.round(durationNs / 1000000);

  // HTTP status
  const httpStatus = meta['http.status_code'] || metrics['http.status_code'];

  // Trace ID
  const traceId = trace.trace_id || rootSpan.trace_id;

  // Timestamp
  const startTime = rootSpan.start;
  const timestamp = startTime ? new Date(startTime / 1000000).toISOString() : null;

  return {
    traceId: String(traceId),
    status: rootSpan.error === 1 ? 'error' : 'ok',
    httpStatus: httpStatus ? Number(httpStatus) : null,
    endpoint,
    resource: rootSpan.resource,
    service: rootSpan.service,
    durationMs,
    timestamp,
    error,
    datadogUrl: `https://app.datadoghq.com/apm/trace/${traceId}`
  };
}

/**
 * Detect format and parse trace accordingly
 */
function parseTrace(trace) {
  // List format has 'attributes' key
  if (trace.attributes) {
    return parseListTrace(trace);
  }
  // Spans format has 'spans' key or trace_id at root
  if (trace.spans || trace.trace_id) {
    return parseSpansTrace(trace);
  }
  // Unknown format, return minimal info
  return {
    traceId: 'unknown',
    status: 'unknown',
    httpStatus: null,
    endpoint: '',
    resource: '',
    service: '',
    durationMs: 0,
    timestamp: null,
    error: null,
    datadogUrl: ''
  };
}

function formatDuration(ms) {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(2)}s`;
  return `${(ms / 60000).toFixed(2)}m`;
}

function formatRelativeTime(isoString) {
  if (!isoString) return 'unknown';
  const date = new Date(isoString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  return `${diffDays}d ago`;
}

/**
 * Deduplicate traces by traceId, keeping only the root span (with http info)
 */
function deduplicateTraces(traces) {
  const seen = new Map();
  for (const trace of traces) {
    const existing = seen.get(trace.traceId);
    // Keep the trace with more info (has endpoint/httpStatus)
    if (!existing || (trace.httpStatus && !existing.httpStatus)) {
      seen.set(trace.traceId, trace);
    }
  }
  return Array.from(seen.values());
}

async function main() {
  let input = '';

  // Read from stdin
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  try {
    const data = JSON.parse(input);

    // Handle different response structures
    let traces = [];

    // List format: { traces: [...] }
    if (data.traces && Array.isArray(data.traces)) {
      traces = data.traces;
    }
    // Array format: [{ attributes: ... }] or [{ spans: ... }]
    else if (Array.isArray(data)) {
      traces = data;
    }
    // Data wrapper: { data: [...] }
    else if (data.data && Array.isArray(data.data)) {
      traces = data.data;
    }
    // Single trace with spans
    else if (data.spans) {
      traces = [data];
    }

    let parsed = traces.map(parseTrace);

    // Deduplicate by traceId (API may return multiple spans per trace)
    parsed = deduplicateTraces(parsed);

    // Output both JSON and human-readable format
    const output = {
      count: parsed.length,
      traces: parsed,
      summary: parsed.map((t, i) => ({
        index: i + 1,
        endpoint: t.endpoint,
        status: t.status,
        httpStatus: t.httpStatus,
        duration: formatDuration(t.durationMs),
        time: formatRelativeTime(t.timestamp),
        error: t.error ? t.error.type : null,
        url: t.datadogUrl
      }))
    };

    console.log(JSON.stringify(output, null, 2));
  } catch (err) {
    console.error(JSON.stringify({
      error: 'Failed to parse trace data',
      message: err.message,
      inputPreview: input.slice(0, 200)
    }, null, 2));
    process.exit(1);
  }
}

main();
