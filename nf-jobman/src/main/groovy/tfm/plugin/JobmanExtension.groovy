/*
 * nf-jobman - TFM plugin prototype
 */

package tfm.plugin

import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import nextflow.Session
import nextflow.plugin.extension.Function
import nextflow.plugin.extension.PluginExtensionPoint

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * Extension functions exposed by nf-jobman.
 *
 * Prototype:
 * Nextflow -> plugin function -> Jobman REST API.
 */
class JobmanExtension extends PluginExtensionPoint {

    @Override
    protected void init(Session session) {
    }

    @Function
    String sayHello(String target) {
        final msg = "Hello, ${target}!"
        println msg
        return msg
    }

    /**
     * Submit a command to Jobman and wait until the job reaches SUCCESS.
     *
     * Default image:
     * - library-batch-public/ubuntu-python:latest
     *
     * Example:
     * jobmanSubmit('job-test', 'python3 --version')
     *
     * Example with explicit image:
     * jobmanSubmit('job-test-ts', 'TotalSegmentator --version', 'no-gpu', 'library-batch-public/totalsegmentator:2.14.0')
     */
    @Function
    String jobmanSubmit(
        String jobName,
        String command,
        String resources = 'no-gpu',
        String image = 'library-batch-public/ubuntu-python:latest'
    ) {
        return submitAndWait(jobName, command, resources, image)
    }

    private String submitAndWait(String jobName, String command, String resources, String image) {
        final String baseUrl = requireEnv('JOBMAN_BASE_URL').replaceAll('/+$', '')
        final String token = requireEnv('JOBMAN_SERVICE_API_TOKEN')

        println "=== nf-jobman: submit ==="
        println "Job name: ${jobName}"
        println "Resources: ${resources}"
        println "Image: ${image}"
        println "Jobman URL: ${baseUrl}"
        println "Command:"
        println command

        final Map payload = [
            jobName     : jobName,
            image       : image,
            resources   : resources,
            commandArgs : ['bash', '-lc', command],
            datasetsList: '',
            dryRun      : false,
            annotations : JsonOutput.toJson([
                origen: 'tfm',
                test  : 'demo31-e2e-final'
            ]),
            env         : [
                [
                    name : 'TEST_MODE',
                    value: 'true'
                ]
            ]
        ]

        println "=== nf-jobman: payload ==="
        println JsonOutput.prettyPrint(JsonOutput.toJson(payload))

        final Object submitResponse = requestJson('POST', "${baseUrl}/jobs/", token, payload, false)
        println "=== nf-jobman: submit response ==="
        println JsonOutput.prettyPrint(JsonOutput.toJson(submitResponse))

        waitUntilSuccess(baseUrl, token, jobName)

        final String logs = getLogs(baseUrl, token, jobName)

        println "=== nf-jobman: job completed ==="
        println "Job name: ${jobName}"

        return logs
    }

    private void waitUntilSuccess(String baseUrl, String token, String jobName) {
        final long timeoutMillis = 900_000L
        final long pollMillis = 5_000L
        final long start = System.currentTimeMillis()

        String lastStatus = null

        while (true) {
            final Map details = getJobDetails(baseUrl, token, jobName)
            final String status = (details.status ?: 'UNKNOWN').toString()

            if (status != lastStatus) {
                println "=== nf-jobman: status ${jobName}: ${status} ==="
                println JsonOutput.prettyPrint(JsonOutput.toJson(details))
                lastStatus = status
            }
            else {
                println "=== nf-jobman: status ${jobName}: ${status} ==="
            }

            final String normalized = status.toLowerCase()

            if (normalized in ['success', 'succeeded', 'completed', 'complete']) {
                return
            }

            if (normalized in ['failed', 'error', 'pending - error']) {
                throw new RuntimeException("Jobman job ${jobName} failed with status: ${status}")
            }

            if (System.currentTimeMillis() - start > timeoutMillis) {
                throw new RuntimeException("Timeout waiting for Jobman job: ${jobName}")
            }

            sleep(pollMillis)
        }
    }

    private Map getJobDetails(String baseUrl, String token, String jobName) {
        final String encoded = URLEncoder.encode(jobName, StandardCharsets.UTF_8.toString())
        final Object response = requestJson('GET', "${baseUrl}/jobs/${encoded}/", token, null, true)

        if (response instanceof Map && response.transientPending == true) {
            return [
                name: jobName,
                status: 'PENDING',
                transientPending: true,
                message: response.message
            ]
        }

        if (response instanceof Map && response.data instanceof Map) {
            return response.data as Map
        }

        if (response instanceof Map) {
            return response as Map
        }

        return [name: jobName, status: 'UNKNOWN', raw: response]
    }

    private String getLogs(String baseUrl, String token, String jobName) {
        final String encoded = URLEncoder.encode(jobName, StandardCharsets.UTF_8.toString())
        final String raw = requestText('GET', "${baseUrl}/jobs/${encoded}/logs/", token, null, false)

        println "=== nf-jobman: logs raw ==="
        println raw

        try {
            final Object parsed = new JsonSlurper().parseText(raw)

            if (parsed instanceof Map) {
                final String stdout = parsed.stdOut?.toString() ?: ''
                final String stderr = parsed.stdErr?.toString() ?: ''

                println "=== nf-jobman: stdout ==="
                println stdout

                if (stderr) {
                    println "=== nf-jobman: stderr ==="
                    println stderr
                }

                return stdout + (stderr ? "\nSTDERR:\n${stderr}" : '')
            }
        }
        catch (Throwable ignored) {
            // Return raw logs if Jobman does not return JSON.
        }

        return raw
    }

    private Object requestJson(String method, String url, String token, Map payload, boolean allowTransientPending) {
        final String text = requestText(method, url, token, payload, allowTransientPending)

        if (!text?.trim()) {
            return [:]
        }

        try {
            return new JsonSlurper().parseText(text)
        }
        catch (Throwable ignored) {
            return [raw: text]
        }
    }

    private String requestText(String method, String url, String token, Map payload, boolean allowTransientPending) {
        final HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection()

        conn.setRequestMethod(method)
        conn.setConnectTimeout(30_000)
        conn.setReadTimeout(30_000)
        conn.setRequestProperty('Authorization', "ApiToken ${token}")

        if (payload != null) {
            final byte[] bytes = JsonOutput.toJson(payload).getBytes(StandardCharsets.UTF_8)
            conn.setDoOutput(true)
            conn.setRequestProperty('Content-Type', 'application/json')
            conn.getOutputStream().write(bytes)
        }

        final int code = conn.getResponseCode()
        final InputStream stream = code >= 400 ? conn.getErrorStream() : conn.getInputStream()
        final String body = stream != null ? stream.getText('UTF-8') : ''

        if (code >= 400) {
            if (allowTransientPending && code == 400 && body.contains("Can't get the pods list for job")) {
                return JsonOutput.toJson([
                    transientPending: true,
                    status: 'PENDING',
                    message: body
                ])
            }

            throw new RuntimeException("HTTP ${code} calling ${method} ${url}\n${body}")
        }

        return body
    }

    private String requireEnv(String name) {
        final String value = System.getenv(name)

        if (!value) {
            throw new IllegalStateException("Missing required environment variable: ${name}")
        }

        return value
    }
}
