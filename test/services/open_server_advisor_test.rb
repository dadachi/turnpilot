require "test_helper"

class OpenServerAdvisorTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 4, 12, 0, 0)
  SHOP = "8f4c2b10-0000-4000-8000-000000000001".freeze

  ADVICE = {
    "advise" => true,
    "text" => "Open a second prep station.",
    "rationale" => "6 cooking vs 2 completed.",
    "suggested_action" => "open_prep_station"
  }.freeze

  def stubbing(receiver, name, impl)
    original = receiver.singleton_method(name)
    receiver.define_singleton_method(name, impl)
    yield
  ensure
    receiver.define_singleton_method(name, original)
  end

  def with_gemma(result)
    stubbing(GemmaClient, :advise, ->(*, **) { result }) do
      stubbing(Turbo::StreamsChannel, :broadcast_prepend_to, ->(*, **) { nil }) do
        yield
      end
    end
  end

  # Backlog of `cooking` cooking orders + `completed` recent completions.
  def make_backlog(cooking:, completed:)
    cooking.times { Order.create!(status: :prepared, shop_id: SHOP, prepared_at: NOW - 120) }
    completed.times { Order.create!(status: :completed, shop_id: SHOP, prepared_at: NOW - 600, completed_at: NOW - 120) }
  end

  test "advises opening a server when cooking backlog outpaces completions" do
    make_backlog(cooking: 6, completed: 2)
    advisory = nil
    with_gemma(ADVICE) do
      assert_difference -> { Advisory.count }, 1 do
        advisory = OpenServerAdvisor.for(SHOP, now: NOW)
      end
    end
    assert_equal "open_server", advisory.kind
    assert_nil advisory.order, "shop-level advisory has no order"
    assert_equal SHOP, advisory.shop_id
  end

  test "stays quiet when the backlog is small" do
    make_backlog(cooking: 3, completed: 0)
    with_gemma(ADVICE) do
      assert_no_difference -> { Advisory.count } do
        assert_nil OpenServerAdvisor.for(SHOP, now: NOW)
      end
    end
  end

  test "stays quiet when completions keep pace with the backlog" do
    make_backlog(cooking: 6, completed: 8)
    with_gemma(ADVICE) do
      assert_nil OpenServerAdvisor.for(SHOP, now: NOW)
    end
  end

  test "suppresses a repeat open_server advisory within the window" do
    make_backlog(cooking: 6, completed: 1)
    with_gemma(ADVICE) do
      assert_not_nil OpenServerAdvisor.for(SHOP, now: NOW)
      assert_no_difference -> { Advisory.count } do
        assert_nil OpenServerAdvisor.for(SHOP, now: NOW), "already advised this window"
      end
    end
  end

  test "respects a Gemma advise:false veto" do
    make_backlog(cooking: 6, completed: 1)
    with_gemma(ADVICE.merge("advise" => false)) do
      assert_no_difference -> { Advisory.count } do
        assert_nil OpenServerAdvisor.for(SHOP, now: NOW)
      end
    end
  end
end
