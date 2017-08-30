require "spec_helper"

describe "process mode" do
  let(:callback_invocations) { @callback_invocations ||= [] }

  before do
    Postqueue.on "op" do |op, entity_ids|
      callback_invocations << [ op, entity_ids ]
    end
    @queue = Postqueue.new
  end

  let(:queue) { @queue }

  context "when enqueuing in sync mode" do
    before do
      queue.processing :sync
      queue.enqueue op: "op", entity_id: 12
    end

    it "processed the items" do
      expect(callback_invocations.length).to eq(1)
    end

    it "removed all items" do
      expect(queue.items.count).to eq(0)
    end
  end

  context "when enqueuing in test mode" do
    before do
      queue.processing :verify
      queue.enqueue op: "op", entity_id: 12
    end

    it "does not process the items" do
      expect(callback_invocations.length).to eq(0)
    end

    it "does not remove items" do
      expect(queue.items.count).to eq(1)
    end

    it "raises an error for invalid ops" do
      expect do
        queue.enqueue op: "invalid", entity_id: 12
      end.to raise_error(Postqueue::MissingHandler)
    end
  end
end
