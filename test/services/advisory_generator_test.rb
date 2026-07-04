require "test_helper"

# Exercises the advisory trigger without touching Ollama or the view layer:
# GemmaClient.advise and the Turbo broadcast are swapped out, so these are fast,
# deterministic, and offline. (Minitest 6 dropped Object#stub, so we swap the
# singleton method ourselves and restore it in an ensure.)
class AdvisoryGeneratorTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)

  ADVICE = {
    "advise" => true,
    "text" => "Call queue #7 to the counter now.",
    "rationale" => "Waited 11 min vs 6 min baseline.",
    "suggested_action" => "page_customer"
  }.freeze

  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  # An order that's been cooking 11 min (past the 9-min flag window).
  def flagged_order
    Order.create!(status: :prepared, queue_number: "7", shop_id: SHOP,
                  joined_at: NOW - 12 * 60, prepared_at: NOW - 11 * 60)
  end

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  # Stub Gemma to return `result`, and no-op the broadcast.
  def with_gemma(result)
    stubbing(GemmaClient, :advise, ->(*, **) { result }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, ->(*, **) { nil }) do
        yield
      end
    end
  end

  test "creates a pending walk_away_risk advisory from the Gemma result" do
    order = flagged_order
    advisory = nil
    with_gemma(ADVICE) do
      assert_difference -> { order.advisories.count }, 1 do
        advisory = AdvisoryGenerator.for(order, now: NOW)
      end
    end
    assert_equal "walk_away_risk", advisory.kind
    assert advisory.pending?
    assert_equal SHOP, advisory.shop_id, "advisory is stamped with the order's shop"
    assert_equal ADVICE["text"], advisory.text
    assert_equal ADVICE["rationale"], advisory.rationale
    assert_equal ADVICE["suggested_action"], advisory.suggested_action
  end

  test "broadcasts the new advisory to the console stream" do
    order = flagged_order
    captured = []
    recorder = ->(stream, **opts) { captured << [ stream, opts[:target] ] }
    stubbing(GemmaClient, :advise, ->(*, **) { ADVICE }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, recorder) do
        AdvisoryGenerator.for(order, now: NOW)
      end
    end
    assert_equal [ [ "console", "advisories" ] ], captured
  end

  test "missing keys degrade to empty strings, never nil" do
    order = flagged_order
    advisory = nil
    with_gemma({ "advise" => true }) do
      advisory = AdvisoryGenerator.for(order, now: NOW)
    end
    assert_equal "", advisory.text
    assert_equal "", advisory.rationale
    assert_equal "", advisory.suggested_action
  end

  test "stays quiet (nil, no persist, no Gemma call) when a similar advisory was overridden" do
    order = flagged_order
    order.advisories.create!(kind: "walk_away_risk", status: :overridden, text: "earlier")
    called = false
    stubbing(GemmaClient, :advise, ->(*, **) { called = true; ADVICE }) do
      assert_no_difference -> { Advisory.count } do
        assert_nil AdvisoryGenerator.for(order, now: NOW)
      end
    end
    assert_not called, "Gemma must not be called while suppressed"
  end

  test "does not advise when Gemma returns advise:false" do
    order = flagged_order
    with_gemma(ADVICE.merge("advise" => false)) do
      assert_no_difference -> { Advisory.count } do
        assert_nil AdvisoryGenerator.for(order, now: NOW)
      end
    end
  end

  test "treats a stringy negative advise as false, but ambiguous as true" do
    order = flagged_order
    with_gemma(ADVICE.merge("advise" => "no")) do
      assert_nil AdvisoryGenerator.for(order, now: NOW)
    end
    with_gemma(ADVICE.merge("advise" => "affirmative")) do
      assert_not_nil AdvisoryGenerator.for(order, now: NOW), "ambiguous defaults to advising"
    end
  end

  test "returns nil and persists nothing when Gemma errors" do
    order = flagged_order
    raiser = ->(*, **) { raise GemmaClient::Error, "ollama unreachable" }
    result = :unset
    stubbing(GemmaClient, :advise, raiser) do
      assert_no_difference -> { Advisory.count } do
        result = AdvisoryGenerator.for(order, now: NOW)
      end
    end
    assert_nil result
  end
end
