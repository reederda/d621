require 'test_helper'
require "danbooru/paginator/pagination_error"

module PostSets
  class PostTest < ActiveSupport::TestCase
    context "In all cases" do
      setup do
        @user = FactoryBot.create(:user)
        CurrentUser.user = @user
        CurrentUser.ip_addr = "127.0.0.1"

        @post_1 = FactoryBot.create(:post, tag_string: "a")
        @post_2 = FactoryBot.create(:post, tag_string: "b")
        @post_3 = FactoryBot.create(:post, tag_string: "c")
      end

      teardown do
        CurrentUser.user = nil
        CurrentUser.ip_addr = nil
      end

      context "a set for page 2" do
        setup do
          @set = PostSets::Post.new("", 2, 1)
        end

        should "return the second element" do
          assert_equal(@post_2.id, @set.posts.first.id)
        end
      end

      context "a set for the 'a' tag query" do
        setup do
          @post_4 = FactoryBot.create(:post, tag_string: "a")
          @post_5 = FactoryBot.create(:post, tag_string: "a")
        end

        context "with no page" do
          setup do
            @set = PostSets::Post.new("a")
          end

          should "return the first element" do
            assert_equal(@post_5.id, @set.posts.first.id)
          end
        end

        context "for before the first element" do
          setup do
            @set = PostSets::Post.new("a", "b#{@post_5.id}", 1)
          end

          should "return the second element" do
            assert_equal(@post_4.id, @set.posts.first.id)
          end
        end

        context "for after the second element" do
          setup do
            @set = PostSets::Post.new("a", "a#{@post_4.id}", 1)
          end

          should "return the first element" do
            assert_equal(@post_5.id, @set.posts.first.id)
          end
        end
      end

      context "a set for the 'a b' tag query" do
        setup do
          @set = PostSets::Post.new("a b")
        end

        should "know it isn't a single tag" do
          assert_not(@set.is_single_tag?)
        end
      end

      context "a set going to the 1,001st page" do
        setup do
          @set = PostSets::Post.new("a", 1_001)
        end

        should "fail" do
          assert_raises(Danbooru::Paginator::PaginationError) do
            @set.posts
          end
        end
      end

      context "a set for the 'a' tag query" do
        setup do
          @set = PostSets::Post.new("a")
        end

        should "know it is a single tag" do
          assert(@set.is_single_tag?)
        end

        should "normalize its tag query" do
          assert_equal("a", @set.tag_string)
        end

        should "know the count" do
          assert_equal(1, @set.posts.total_count)
        end

        should "find the posts" do
          assert_equal(@post_1.id, @set.posts.first.id)
        end

        context "that has a matching wiki page" do
          setup do
            @wiki_page = FactoryBot.create(:wiki_page, title: "a")
          end

          should "find the wiki page" do
            assert_not_nil(@set.wiki_page)
            assert_equal(@wiki_page.id, @set.wiki_page.id)
          end
        end

        context "that has a matching artist" do
          setup do
            @artist = FactoryBot.create(:artist, name: "a")
          end

          should "find the artist" do
            assert_not_nil(@set.artist)
            assert_equal(@artist.id, @set.artist.id)
          end
        end
      end

      context "#per_page method" do
        should "take the limit from the params first, then the limit:<n> metatag, then the account settings" do
          set = PostSets::Post.new("a limit:23 b", 1, 42)
          assert_equal(42, set.per_page)

          set = PostSets::Post.new("a limit:23 b", 1, nil)
          assert_equal(23, set.per_page)

          set = PostSets::Post.new("a", 1, nil)
          assert_equal(CurrentUser.user.per_page, set.per_page)
        end
      end
    end
  end
end
