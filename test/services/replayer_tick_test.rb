require "test_helper"

# End-to-end reproducibility of the demo path: seed -> advance -> fire advisories.
# GemmaClient and the Turbo broadcasts are stubbed, so this is offline and deterministic.
class ReplayerTickTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)

  ADVICE = {
    "advise" => true, "text" => "Check the kitchen.",
    "rationale" => "cooking past normal", "suggested_action" => "check_kitchen"
  }.freeze

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  def with_stubs
    stubbing(GemmaClient, :advise, ->(*, **) { ADVICE }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, ->(*, **) { nil }) do
        stubbing(Turbo::StreamsChannel, :broadcast_replace_to, ->(*, **) { nil }) do
          yield
        end
      end
    end
  end

  def walk_away_queues(advisories)
    advisories.select { |a| a.kind == "walk_away_risk" }.map { |a| a.order.queue_number }.sort
  end

  test "tick fires both advisory kinds from the seeded rush" do
    Replayer.seed(now: NOW)
    advisories = with_stubs { Replayer.tick(now: NOW) }

    kinds = advisories.map(&:kind).tally
    assert_operator kinds["walk_away_risk"].to_i, :>=, 1, "at least one walk-away advisory"
    assert_equal 1, kinds["open_server"], "one shop-level open-server advisory"
  end

  test "a second immediate tick adds nothing (pending + window suppression)" do
    Replayer.seed(now: NOW)
    with_stubs do
      Replayer.tick(now: NOW)
      assert_no_difference -> { Advisory.count } do
        Replayer.tick(now: NOW)
      end
    end
  end

  test "tick resolves advisories whose order finished cooking before staff acted" do
    Replayer.seed(now: NOW)
    with_stubs do
      fired = Replayer.tick(now: NOW).select { |a| a.kind == "walk_away_risk" }
      assert_not_empty fired
      assert fired.all?(&:pending?), "freshly fired advisories start pending"

      # Jump well past the rush: every seeded order has finished cooking by now.
      Replayer.tick(now: NOW + 1.hour)

      fired.each(&:reload)
      assert fired.all?(&:resolved?), "advisories for completed orders auto-resolve"
      assert_equal 0, Advisory.pending.where.not(order_id: nil).count,
                   "no order-scoped advisory should still demand action once its order is done"
    end
  end

  test "reproducible: same seed + now flags the same orders" do
    Replayer.seed(now: NOW)
    first = with_stubs { walk_away_queues(Replayer.tick(now: NOW)) }

    Replayer.seed(now: NOW) # reset and replay identically
    second = with_stubs { walk_away_queues(Replayer.tick(now: NOW)) }

    assert_not_empty first
    assert_equal first, second
  end
end
