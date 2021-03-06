require 'spec_helper'

describe Sidekiq::LimitFetch::Queues do
  subject { described_class.new options }

  let(:queues)   { %w[queue1 queue2] }
  let(:limits)   {{ 'queue1' => 3 }}
  let(:strict)   { true }
  let(:blocking) {}

  let(:options) do
    { queues:   queues,
      limits:   limits,
      strict:   strict,
      blocking: blocking,
      namespace: Sidekiq::LimitFetch::Redis.determine_namespace }
  end

  it 'should acquire queues' do
    subject.acquire
    Sidekiq::Queue['queue1'].probed.should == 1
    Sidekiq::Queue['queue2'].probed.should == 1
  end

  it 'should acquire dynamically blocking queues' do
    subject.acquire
    Sidekiq::Queue['queue1'].probed.should == 1
    Sidekiq::Queue['queue2'].probed.should == 1

    Sidekiq::Queue['queue1'].block

    subject.acquire
    Sidekiq::Queue['queue1'].probed.should == 2
    Sidekiq::Queue['queue2'].probed.should == 1
  end

  it 'should block except given queues' do
    Sidekiq::Queue['queue1'].block_except 'queue2'
    subject.acquire
    Sidekiq::Queue['queue1'].probed.should == 1
    Sidekiq::Queue['queue2'].probed.should == 1

    Sidekiq::Queue['queue1'].block_except 'queue404'
    subject.acquire
    Sidekiq::Queue['queue1'].probed.should == 2
    Sidekiq::Queue['queue2'].probed.should == 1
  end

  it 'should release queues' do
    subject.acquire
    subject.release_except nil
    Sidekiq::Queue['queue1'].probed.should == 0
    Sidekiq::Queue['queue2'].probed.should == 0
  end

  it 'should release queues except selected' do
    subject.acquire
    subject.release_except 'queue:queue1'
    Sidekiq::Queue['queue1'].probed.should == 1
    Sidekiq::Queue['queue2'].probed.should == 0
  end

  it 'should release when no queues was acquired' do
    queues.each {|name| Sidekiq::Queue[name].pause }
    subject.acquire
    -> { subject.release_except nil }.should_not raise_exception
  end

  context 'blocking' do
    let(:blocking) { %w(queue1) }

    it 'should acquire blocking queues' do
      3.times { subject.acquire }
      Sidekiq::Queue['queue1'].probed.should == 3
      Sidekiq::Queue['queue2'].probed.should == 1
    end
  end

  it 'should set limits' do
    subject
    Sidekiq::Queue['queue1'].limit.should == 3
    Sidekiq::Queue['queue2'].limit.should_not be
  end

  context 'without strict flag' do
    let(:strict) { false }

    it 'should retrieve weighted queues' do
      subject.ordered_queues.should =~ %w(queue1 queue2)
    end
  end

  it 'with strict flag should retrieve strictly ordered queues' do
    subject.ordered_queues.should == %w(queue1 queue2)
  end
end
