require 'CSV'

$option = {
  debug: false,
  base_shottype: :Youmu, # 基準とする機体
  base_6lives_twcscore: 15.96, # 基準とする残6TWCスコア
  s9r1_time_multiplier: 0.02, # S9R1の経過秒数の係数
  _7lives_twcscore: 60, # 霊夢/映姫残7のTWCScore
  match_time: -1, # 0以下: FR
  notFR_N: 10000, # FRでない場合の試行回数
  always_final_extend: false, # 常に最終エクステンド到達とする
  output_dir: 'E:/research/twc2024/out',
  csv_path: 'E:/research/twc2024/PoFV Lunatic Survival TWCScore 2024 Revision - test play.csv',
}

def ms2s(ms)
  return nil if ms.nil?
  ms[/(?:(\d+):)?(\d+):(\d+)/] ? $1.to_i*3600+$2.to_i*60+$3.to_i : 0
end

def s2ms(s)
  sprintf("%02d:%02d", s/60, s%60)
end

# 6面までに死ななければ通す。
# それ以降は、更新が期待できない場合リセットする。
# FRは最後まで通す

module Th09LunaticSurvival
  class Match < Enumerator::Lazy
    @@shottype_names = %i[Reimu Marisa Sakuya Youmu Reisen Cirno Lyrica Mystia Tewi Aya Medicine Yuuka Komachi Eiki]
    @@shottype_data = @@shottype_names.map{|key|
      h = { name: "", s1_5: [], s6: [], s7: [], s8: [], s9: [], }
      [key, h]
    }.to_h

    def self.shottype_names; @@shottype_names; end
    def self.shottype_data; @@shottype_data; end
    
    def self.import_csv(csv)
      _h = CSV.read(csv).map{|key, *values| [key, values] }.to_h
      _h["S1R1"].size.times{|i|
        st = _h["ShotType"][i]
        next if st.nil?
        name = st[/\w+/]
        h = @@shottype_data[name.intern]
        h[:name] = name
    
        if !_h["S1R1"][i].nil?
          raise if _h["S5 End Score"][i].nil?
          ts = [ms2s(_h["S1R1"][i]) + ms2s(_h["S2R1"][i]) + ms2s(_h["S3R1"][i]) + ms2s(_h["S4R1"][i]) + ms2s(_h["S5R1"][i])]
          s = _h["S5 End Score"][i].to_i
          h[:s1_5].push([ts,s])
        end
        if !_h["S6R1"][i].nil?
          raise TypeError, _h["ShotType"][i] if _h["S6 End Score"][i].nil? || _h["S5 End Score"][i].nil?
          ts = [ms2s(_h["S6R1"][i]), ms2s(_h["S6R2"][i]), ms2s(_h["S6R3"][i])].compact
          s = _h["S6 End Score"][i].to_i - _h["S5 End Score"][i].to_i
          h[:s6].push([ts,s])
        end
        if !_h["S7R1"][i].nil?
          raise TypeError, _h["ShotType"][i] if _h["S7 End Score"][i].nil? || _h["S6 End Score"][i].nil?
          ts = [ms2s(_h["S7R1"][i]), ms2s(_h["S7R2"][i]), ms2s(_h["S7R3"][i])].compact
          s = _h["S7 End Score"][i].to_i - _h["S6 End Score"][i].to_i
          h[:s7].push([ts,s])
        end
        if !_h["S8R1"][i].nil?
          raise TypeError, _h["ShotType"][i] if _h["S8 End Score"][i].nil? || _h["S7 End Score"][i].nil?
          ts = [ms2s(_h["S8R1"][i]), ms2s(_h["S8R2"][i]), ms2s(_h["S8R3"][i])].compact
          s = _h["S8 End Score"][i].to_i - _h["S7 End Score"][i].to_i
          h[:s8].push([ts,s])
        end
        if !_h["S9R1"][i].nil?
          raise TypeError, _h["ShotType"][i] if _h["S9 End Score"][i].nil? || _h["S8 End Score"][i].nil?
          ts = [ms2s(_h["S9R1"][i]), ms2s(_h["S9R2"][i]), ms2s(_h["S9R3"][i]), ms2s(_h["S9R4"][i])].compact
          s = _h["S9 End Score"][i].to_i - _h["S8 End Score"][i].to_i
          h[:s9].push([ts,s])
        end
        @@shottype_data
      }
    end
    
    def initialize(shottype)
      @stage_end_time = 6
      @story_end_time = 40
      @debug = $option[:debug]
      @always_final_extend = $option[:always_final_extend]
      @match_time = $option[:match_time]
      @data = @@shottype_data[shottype]
    end

    def is_fr
      @remaining_match_time < 0
    end

    def test(*story_data)
      @remaining_match_time = @match_time

      @max_remaining_lives = -1
      @max_s9r1_time = -1
      loop {
        expected_lives = 7
        total_score = 0
        s9r1_time = -1
        reset = false
        story_data.each.with_index(5){|stage_data, stage|
          round_times, stage_score = stage_data
          round_times.each.with_index(1){|round_time, round|
            # ラウンド終了ごとに残り時間を消費する
            @remaining_match_time -= round_time
            # S9R1
            s9r1_time = round_time if stage == 9 && round == 1
            # 2ラウンド目以降
            if round > 1
              # 期待残機数-1
              expected_lives -= 1
              if is_fr # FRならリセットしない
                # 期待残機数6以上かつS9R1更新できるならリセットしない
              elsif expected_lives >= 6 && s9r1_time > @max_s9r1_time
                # 6面で死ぬか残機数の更新が期待できない時リセット
              elsif stage == 6 || expected_lives <= @max_remaining_lives
                reset = true
              end
            end
            puts("\t#{@max_remaining_lives}\t#{@max_s9r1_time}\t#{s2ms(@remaining_match_time)}\t#{stage}r#{round}\t#{expected_lives}") if @debug
            break if reset
          }
          if reset
            puts("\treset") if @debug
            break 
          end
          total_score += stage_score
          sec = case stage
          when 5; @stage_end_time * 5
          when 9; @story_end_time
          else @stage_end_time
          end
          @remaining_match_time -= sec
          puts("#{@data[:name]}\t#{@max_remaining_lives}\t#{@max_s9r1_time}\t#{s2ms(@remaining_match_time)}\t#{stage}\t#{expected_lives}\t#{total_score}") if @debug
        }
        next if reset
        if @always_final_extend
          remaining_lives = expected_lives
        else
          remaining_lives = 2 + ([9, total_score/1000].min + 1) / 2 - (7 - expected_lives)
        end
        # 残機数が同じかそれ以上の場合、更新
        if remaining_lives == @max_remaining_lives
          @max_s9r1_time = [@max_s9r1_time, s9r1_time].max
          puts("\tupdate: #{@max_remaining_lives}\t#{@max_s9r1_time}") if @debug
        elsif remaining_lives > @max_remaining_lives
          @max_remaining_lives = remaining_lives
          @max_s9r1_time = s9r1_time
          puts("\tupdate: #{@max_remaining_lives}\t#{@max_s9r1_time}") if @debug
        end
        # 残り時間0未満(final run)なら試合終了
        break if is_fr
      }
      puts("    final: #{@max_remaining_lives}\t#{@max_s9r1_time}") if @debug
      [@max_remaining_lives, @max_s9r1_time]
    end

    def sample
      test(@data[:s1_5].sample, @data[:s6].sample, @data[:s7].sample, @data[:s8].sample, @data[:s9].sample)
    end

    def each
      return to_enum if !block_given?

      enum = if @debug
        Enumerator.new{|y| y << sample }
      elsif @match_time <= 0
        Enumerator.new{|y|
          @data[:s1_5].product(@data[:s6], @data[:s7], @data[:s8], @data[:s9]).each{|s15_6_7_8_9|
            y << test(*s15_6_7_8_9)
          }
        }
      else
        Enumerator.new{|y| $option[:notFR_N].times{ y << sample }}
      end
      enum.each{|res| yield res }
    end

  end

  class Simulator
    def initialize(shottype, m: $option[:_7lives_twcscore], s9r1_time_multiplier: $option[:s9r1_time_multiplier])
      @shottype = shottype
      @m = m
      @s9r1_time_multiplier = s9r1_time_multiplier
      @csv = File.join($option[:output_dir], "#{shottype}.txt")
      @res = []
    end

    def run
      return @res if !@res.empty?
      @res = []
      match = Match.new(@shottype)
      match.each{|res|
        @res << res
      }
      @res
    end

    def out
      run() if @res.empty?
      CSV.open(@csv, 'w'){|c|
        @res.each{|a| c << a }
      }
      @res
    end

    def read
      @res = CSV.read(@csv).map{|a| a.map &:to_i }
    end

    # 残機統計
    def life_stats
      run()
      s = "# Lives\t"
      h = @res.group_by{|lives, round_time| lives }
      a = (0..7).map{|i|
        count = h.key?(i) ? h[i].size : 0
        sprintf("%d:%4.1f%%", i, count.fdiv(@res.size)*100)
      } + ["ave:#{@res.sum{|lives, round_time| lives }.fdiv(@res.size)}"]
      s += a * ", "
      s
    end

    # 突破ラウンド統計
    def round_stats
      s = "# Rounds\t"
      s += (6..9).map{|stage|
        key = "s#{stage}".intern
        round_times_a = Match.shottype_data[@shottype][key].map{|x| x.first }
        h = round_times_a.group_by{|round_times| round_times.size }
        n = stage == 9 ? 4 : 3
        left = (1..n).map{|i| "R#{i}"} * ":"
        right = (1..n).map{|i| h.key?(i) ? h[i].size : 0 } * ":"
        "S#{stage}(#{left}=#{right})"
      } * ", "
      s
    end

    # S9R1統計
    def s9r1_time_stats
      s = "# S9R1 Time\t"
      s9r1_times = Match.shottype_data[@shottype][:s9].map{|x| x.first.first }
      h = {
        max: s9r1_times.max,
        min: s9r1_times.min,
        ave: s9r1_times.sum/s9r1_times.size,
        med: (a = s9r1_times.sort; (a[a.size/2]+a[(a.size-1)/2])/2),
      }
      s += h.map{|k, v| "#{k}:#{s2ms(v)}" } * ", "
      s
    end

    # 統計
    def stats
      [life_stats, round_stats, s9r1_time_stats] * "\n"
    end

    def TWCScore(n, l, s)
      (l == 7 ? @m : n * 0.5**(6-l)) + s * @s9r1_time_multiplier
    end

    # 平均TWCスコアが目標値になる残6TWCスコアの値を求める
    def invert_6lives_TWCScore(target_twcscore)
      run()
      (-1000.0..1000.0).bsearch{|n|
        average_TWCScore(n) > target_twcscore
      }
    end

    # TWCスコアの平均値を求める
    def average_TWCScore(n)
      run()
      twcscore = @res.map{|l, s|
        TWCScore(n, l, s)
      }.sum.fdiv(@res.size)
    end
  end
end

include Th09LunaticSurvival

Match.import_csv($option[:csv_path])

sim = Simulator.new($option[:base_shottype])
target_twcscore = sim.average_TWCScore($option[:base_6lives_twcscore])

Match.shottype_names.each{|st|
  next if st == :Aya || st == :Medicine

  sim = Simulator.new(st)
  printf("%s\t%5.2f\n", st, sim.invert_6lives_TWCScore(target_twcscore))
  puts sim.stats
  puts
}
