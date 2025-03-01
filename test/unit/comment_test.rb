require 'test_helper'

class CommentTest < ActiveSupport::TestCase
  context "A comment" do
    setup do
      user = FactoryBot.create(:user)
      CurrentUser.user = user
      CurrentUser.ip_addr = "127.0.0.1"
    end

    teardown do
      CurrentUser.user = nil
      CurrentUser.ip_addr = nil
    end

    context "created by a limited user" do
      setup do
        Danbooru.config.stubs(:disable_throttles?).returns(false)
      end

      should "fail creation" do
        comment = FactoryBot.build(:comment, post: create(:post))
        comment.save
        assert_equal(["Creator can not yet perform this action. Account is too new."], comment.errors.full_messages)
      end
    end

    context "created by an unlimited user" do
      setup do
        Danbooru.config.stubs(:member_comment_limit).returns(100)
      end

      context "that is then deleted" do
        setup do
          @post = FactoryBot.create(:post)
          @comment = FactoryBot.create(:comment, post_id: @post.id)
          @comment.destroy
          @post.reload
        end

        should "nullify the last_commented_at field" do
          assert_nil(@post.last_commented_at)
        end
      end

      should "be created" do
        post = FactoryBot.create(:post)
        comment = FactoryBot.build(:comment, post: post)
        comment.save
        assert(comment.errors.empty?, comment.errors.full_messages.join(", "))
      end

      should "not validate if the post does not exist" do
        comment = FactoryBot.build(:comment, post_id: -1)

        assert_not(comment.valid?)
        assert_match(/must exist/, comment.errors[:post].join(", "))
      end

      should "not bump the parent post" do
        post = FactoryBot.create(:post)
        comment = FactoryBot.create(:comment, :do_not_bump_post => true, :post => post)
        post.reload
        assert_nil(post.last_comment_bumped_at)

        comment = FactoryBot.create(:comment, :post => post)
        post.reload
        assert_not_nil(post.last_comment_bumped_at)
      end

      should "not bump the post after exceeding the threshold" do
        Danbooru.config.stubs(:comment_threshold).returns(1)
        p = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, :post => p)
        Timecop.travel(2.seconds.from_now) do
          c2 = FactoryBot.create(:comment, :post => p)
        end
        p.reload
        assert_equal(c1.created_at.to_s, p.last_comment_bumped_at.to_s)
      end

      should "always record the last_commented_at properly" do
        post = FactoryBot.create(:post)
        Danbooru.config.stubs(:comment_threshold).returns(1)

        c1 = FactoryBot.create(:comment, :do_not_bump_post => true, :post => post)
        post.reload
        assert_equal(c1.created_at.to_s, post.last_commented_at.to_s)

        Timecop.travel(2.seconds.from_now) do
          c2 = FactoryBot.create(:comment, :post => post)
          post.reload
          assert_equal(c2.created_at.to_s, post.last_commented_at.to_s)
        end
      end

      should "not record the user id of the voter" do
        user = FactoryBot.create(:user)
        user2 = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, post: post)

        CurrentUser.scoped(user2, "127.0.0.1") do
          VoteManager.comment_vote!(user: user2, comment: c1, score: -1)
          c1.reload
          assert_not_equal(user2.id, c1.updater_id)
        end
      end

      should "not allow duplicate votes" do
        user = FactoryBot.create(:user)
        user2 = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, post: post)
        c2 = FactoryBot.create(:comment, post: post)

        CurrentUser.scoped(user2, "127.0.0.1") do
          assert_nothing_raised { VoteManager.comment_vote!(user: user2, comment: c1, score: -1) }
          assert_equal(:need_unvote, VoteManager.comment_vote!(user: user2, comment: c1, score: -1))
          assert_equal(1, CommentVote.count)
          assert_equal(-1, CommentVote.last.score)

          assert_nothing_raised { VoteManager.comment_vote!(user: user2, comment: c2, score: -1) }
          assert_equal(2, CommentVote.count)
        end
      end

      should "not allow upvotes by the creator" do
        user = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, post: post)

        exception = assert_raises(ActiveRecord::RecordInvalid) { VoteManager.comment_vote!(user: user, comment: c1, score: 1) }
        assert_equal("Validation failed: You cannot vote on your own comments", exception.message)
      end

      should "not allow downvotes by the creator" do
        user = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, post: post)

        exception = assert_raises(ActiveRecord::RecordInvalid) { VoteManager.comment_vote!(user: user, comment: c1, score: -1) }
        assert_equal("Validation failed: You cannot vote on your own comments", exception.message)
      end

      should "not allow votes on sticky comments" do
        user = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        c1 = FactoryBot.create(:comment, post: post, is_sticky: true)

        exception = assert_raises(ActiveRecord::RecordInvalid) { VoteManager.comment_vote!(user: user, comment: c1, score: -1) }
        assert_match(/You cannot vote on sticky comments/, exception.message)
      end

      should "allow undoing of votes" do
        user = FactoryBot.create(:user)
        user2 = FactoryBot.create(:user)
        post = FactoryBot.create(:post)
        comment = FactoryBot.create(:comment, post: post)
        CurrentUser.scoped(user2, "127.0.0.1") do
          VoteManager.comment_vote!(user: user2, comment: comment, score: 1)
          comment.reload
          assert_equal(1, comment.score)
          VoteManager.comment_unvote!(user: user2, comment: comment)
          comment.reload
          assert_equal(0, comment.score)
          assert_nothing_raised { VoteManager.comment_vote!(user: user2, comment: comment, score: -1) }
        end
      end

      should "be searchable" do
        c1 = FactoryBot.create(:comment, :body => "aaa bbb ccc")
        c2 = FactoryBot.create(:comment, :body => "aaa ddd")
        c3 = FactoryBot.create(:comment, :body => "eee")

        matches = Comment.search(body_matches: "aaa")
        assert_equal(2, matches.count)
        assert_equal(c2.id, matches.all[0].id)
        assert_equal(c1.id, matches.all[1].id)
      end

      should "default to id_desc order when searched with no options specified" do
        comms = FactoryBot.create_list(:comment, 3)
        matches = Comment.search({})

        assert_equal([comms[2].id, comms[1].id, comms[0].id], matches.map(&:id))
      end

      context "that is edited by a moderator" do
        setup do
          @post = FactoryBot.create(:post)
          @comment = FactoryBot.create(:comment, :post_id => @post.id)
          @mod = FactoryBot.create(:moderator_user)
          CurrentUser.user = @mod
        end

        should "create a mod action" do
          assert_difference("ModAction.count") do
            @comment.update(:body => "nope")
          end
        end

        should "credit the moderator as the updater" do
          @comment.update(body: "test")
          assert_equal(@mod.id, @comment.updater_id)
        end
      end

      context "that is below the score threshold" do
        should "be hidden if not stickied" do
          user = FactoryBot.create(:user, :comment_threshold => 0)
          post = FactoryBot.create(:post)
          comment = FactoryBot.create(:comment, :post => post, :score => -5)

          assert_equal([comment], post.comments.hidden(user))
          assert_equal([], post.comments.visible(user))
        end

        should "be visible if stickied" do
          user = FactoryBot.create(:user, :comment_threshold => 0)
          post = FactoryBot.create(:post)
          comment = FactoryBot.create(:comment, :post => post, :score => -5, :is_sticky => true)

          assert_equal([], post.comments.hidden(user))
          assert_equal([comment], post.comments.visible(user))
        end
      end

      context "that is quoted" do
        should "strip [quote] tags correctly" do
          comment = FactoryBot.create(:comment, body: <<-EOS.strip_heredoc)
            paragraph one

            [quote]
            somebody said:

            blah blah blah
            [/QUOTE]

            paragraph two
          EOS

          assert_equal(<<-EOS.strip_heredoc, comment.quoted_response)
            [quote]
            #{comment.creator_name} said:

            paragraph one

            paragraph two
            [/quote]

          EOS
        end
      end

      context "on a comment locked post" do
        setup do
          @post = create(:post, is_comment_disabled: true)
        end

        should "prevent new comments" do
          comment = FactoryBot.build(:comment, post: @post)
          comment.save
          assert_equal(["Post has comments disabled"], comment.errors.full_messages)
        end
      end
    end

    context "during validation" do
      subject { FactoryBot.build(:comment) }
      should_not allow_value(" ").for(:body)
    end
  end
end
