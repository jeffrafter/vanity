module Vanity
  module Experiment

    # Experiment alternative.  See AbTest#alternatives.
    class Alternative

      def initialize(experiment, id, value) #:nodoc:
        @experiment = experiment
        @id = id
        @value = value
      end

      # Alternative id, only unique for this experiment.
      attr_reader :id
     
      # Alternative value.
      attr_reader :value

      # Number of participants who viewed this alternative.
      def participants
        redis.scard(key("participants")).to_i
      end

      # Number of participants who converted on this alternative.
      def converted
        redis.scard(key("converted")).to_i
      end

      # Number of conversions for this alternative (same participant may be counted more than once).
      def conversions
        redis.get(key("conversions")).to_i
      end

      def participating!(identity)
        redis.sadd key("participants"), identity
      end

      def conversion!(identity)
        if redis.sismember(key("participants"), identity)
          redis.sadd key("converted"), identity
          redis.incr key("conversions")
        end
      end

    protected

      def key(name)
        @experiment.key("alts:#{id}:#{name}")
      end

      def redis
        @experiment.redis
      end

    end

    # The meat.
    class AbTest < Base
      def initialize(*args) #:nodoc:
        super
      end

      # Chooses a value for this experiment.
      #
      # This method returns different values for different identity (see
      # #identify), and consistenly the same value for the same
      # expriment/identity pair.
      #
      # For example:
      #   color = experiment(:which_blue).choose
      def choose
        identity = identify
        alt = alternative_for(identity)
        alt.participating! identity
        alt.value
      end

      # Records a conversion.
      #
      # For example:
      #   experiment(:which_blue).conversion!
      def conversion!
        identity = identify
        alt = alternative_for(identity)
        alt.conversion! identity
        alt.id
      end

      # Call this method once to specify values for the A/B test.  At least two
      # values are required.
      #
      # Call without argument to previously defined alternatives (see Alternative).
      #
      # For example:
      #   experiment "Background color" do
      #     alternatives "red", "blue", "orange"
      #   end
      #
      #   alts = experiment(:background_color).alternatives
      #   puts "#{alts.count} alternatives, with the colors: #{alts.map(&:value).join(", ")}"
      def alternatives(*args)
        args = [true, false] if args.empty?
        @alternatives = []
        args.each_with_index do |arg, i|
          @alternatives << Alternative.new(self, i, arg)
        end
        class << self ; self ; end.send(:define_method, :alternatives) { @alternatives }
        alternatives
      end

      # Sets this test to two alternatives: true and false.
      def true_false
        alternatives true, false
      end

      def report
        alts = alternatives.map { |alt|
          "<dt>Option #{(65 + alt.id).chr}</dt><dd><code>#{CGI.escape_html alt.value.inspect}</code> viewed #{alt.participants} times, converted #{alt.conversions}<dd>"
        }
        %{<dl class="data">#{alts.join}</dl>}
      end

      # Forces this experiment to use a particular alternative. Useful for
      # tests, e.g.
      #
      #   setup do
      #     experiment(:green_button).select(true)
      #   end
      #
      #   def test_shows_green_button
      #     . . .
      #   end
      #
      # Use nil to clear out selection:
      #   teardown do
      #     experiment(:green_button).select(nil)
      #   end
      def chooses(value)
        alternative = alternatives.find { |alt| alt.value == value }
        raise ArgumentError, "No alternative #{value.inspect} for #{name}" unless alternative
        Vanity.context.session[:vanity] ||= {}
        Vanity.context.session[:vanity][id] = alternative.id
      end

      def humanize
        "A/B Test" 
      end

      def save #:nodoc:
        fail "Experiment #{name} needs at least two alternatives" unless alternatives.count >= 2
        super
      end

    private

      # Chooses an alternative for the identity and returns its index. This
      # method always returns the same alternative for a given experiment and
      # identity, and randomly distributed alternatives for each identity (in the
      # same experiment).
      def alternative_for(identity)
        session = Vanity.context.session[:vanity]
        index = session && session[id]
        index ||= Digest::MD5.hexdigest("#{name}/#{identity}").to_i(17) % alternatives.count
        alternatives[index]
      end

    end
  end
end
