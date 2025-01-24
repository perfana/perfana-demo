package afterburner

import io.gatling.javaapi.core.*
import io.gatling.javaapi.http.*
import io.gatling.javaapi.core.CoreDsl.*
import io.gatling.javaapi.http.HttpDsl.*
import java.lang.Exception
import java.time.Duration

class AfterburnerBasicSimulation : Simulation() {

    private val testRunId = System.getProperty("testRunId") ?: "test-run-id-from-script-" + System.currentTimeMillis()

    private val baseUrl = System.getProperty("targetBaseUrl") ?: "http://localhost:8080"

    private val initialUsersPerSecond: Int = (System.getProperty("initialUsersPerSecond") ?: "1").toInt()
    private val targetConcurrency: Int = (System.getProperty("targetConcurrency") ?: "10").toInt()
    private val rampupTimeInSeconds: Long = (System.getProperty("rampupTimeInSeconds") ?: "30").toLong()
    private val constantLoadTimeInSeconds: Long = (System.getProperty("constantLoadTimeInSeconds") ?: "90").toLong()

    private val contentType = "application/json"

    val httpProtocol = http
        .baseUrl(baseUrl)
        .inferHtmlResources()
        .acceptHeader("*/*")
        .contentTypeHeader(contentType)
        .userAgentHeader("curl/7.54.0")
        .header("perfana-test-run-id", testRunId)
        .warmUp("$baseUrl/memory/clear")

    val scn = scenario("AfterburnerBasicSimulation")
        .exec(http("simple_delay")
            .get("/delay?duration=222")
            .header("perfana-request-name", "simple_delay")
            .check(status().shouldBe(200)))
        .pause(1)
        .exec(http("simple_cpu_burn")
            .get("/cpu/magic-identity-check?matrixSize=133")
            .header("perfana-request-name", "simple_cpu_burn")
            .check(status().shouldBe(200)))
        .pause(1)
        .exec(http("flaky_call")
            .get("/flaky?maxRandomDelay=240&flakiness=5")
            .header("perfana-request-name", "flaky_call")
            .check(status().shouldBe(200)))
        .pause(1)
        .exec(http("remote_call_delayed")
            .get("/remote/call?path=remote/call?path=delay")
            .header("perfana-request-name", "remote_call_delayed")
            .check(status().shouldBe(200)))
        .exec(http("memory_churn")
            .get("/memory/churn?objects=1818")
            .header("perfana-request-name", "memory_churn")
            .check(status().shouldBe(200)))
        .pause(1)

    init {
        println("(ignored) initialUsersPerSecond:     $initialUsersPerSecond")
        println("(ignored) rampupTimeInSeconds:       $rampupTimeInSeconds")
        println("targetConcurrency:         $targetConcurrency")
        println("constantLoadTimeInSeconds: $constantLoadTimeInSeconds")

        setUp(
            scn.injectOpen(
                //atOnceUsers(initialUsersPerSecond),
                //rampUsers(initialUsersPerSecond).during(Duration.ofSeconds(rampupTimeInSeconds)),
                constantUsersPerSec(targetConcurrency.toDouble()).during(Duration.ofSeconds(constantLoadTimeInSeconds))
            ).protocols(httpProtocol)
        )
    }

}

