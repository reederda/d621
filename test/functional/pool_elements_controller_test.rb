require 'test_helper'

class PoolElementsControllerTest < ActionDispatch::IntegrationTest
  context "The pools posts controller" do
    setup do
      @user = travel_to(1.month.ago) {create(:user)}
      @mod = create(:moderator_user)
      as_user do
        @post = create(:post)
        @pool = create(:pool, :name => "abc")
      end
    end

    context "create action" do
      should "add a post to a pool" do
        post_auth pool_element_path, @user, params: {:pool_id => @pool.id, :post_id => @post.id, :format => "json"}
        @pool.reload
        assert_equal([@post.id], @pool.post_ids)
      end

      should "add a post to a pool once and only once" do
        as_user { @pool.add!(@post) }
        post_auth pool_element_path, @user, params: {:pool_id => @pool.id, :post_id => @post.id, :format => "json"}
        @pool.reload
        assert_equal([@post.id], @pool.post_ids)
      end
    end

    context "destroy action" do
      setup do
        as_user { @pool.add!(@post) }
      end

      should "remove a post from a pool" do
        delete_auth pool_element_path, @user, params: {:pool_id => @pool.id, :post_id => @post.id, :format => "json"}
        @pool.reload
        assert_equal([], @pool.post_ids)
      end

      should "do nothing if the post is not a member of the pool" do
        @pool.reload
        as_user do
          @pool.remove!(@post)
        end
        delete_auth pool_element_path, @user, params: {:pool_id => @pool.id, :post_id => @post.id, :format => "json"}
        @pool.reload
        assert_equal([], @pool.post_ids)
      end
    end
  end
end
