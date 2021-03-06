require 'test_helper'

class TagAliasTest < ActiveSupport::TestCase
  context "A tag alias" do
    setup do
      Timecop.travel(1.month.ago) do
        user = FactoryGirl.create(:user)
        CurrentUser.user = user
      end
      CurrentUser.ip_addr = "127.0.0.1"
      MEMCACHE.flush_all
      Delayed::Worker.delay_jobs = false
    end

    teardown do
      CurrentUser.user = nil
      CurrentUser.ip_addr = nil
    end

    context "on validation" do
      subject do
        FactoryGirl.create(:tag, :name => "aaa")
        FactoryGirl.create(:tag, :name => "bbb")
        FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      end

      should allow_value('active').for(:status)
      should allow_value('deleted').for(:status)
      should allow_value('pending').for(:status)
      should allow_value('processing').for(:status)
      should allow_value('queued').for(:status)
      should allow_value('error: derp').for(:status)

      should_not allow_value('ACTIVE').for(:status)
      should_not allow_value('error').for(:status)
      should_not allow_value('derp').for(:status)

      should allow_value(nil).for(:forum_topic_id)
      should_not allow_value(-1).for(:forum_topic_id).with_message("must exist", against: :forum_topic)

      should allow_value(nil).for(:approver_id)
      should_not allow_value(-1).for(:approver_id).with_message("must exist", against: :approver)

      should_not allow_value(nil).for(:creator_id)
      should_not allow_value(-1).for(:creator_id).with_message("must exist", against: :creator)

      should_not allow_mass_assignment_of(:status).as(:member)
    end

    should "populate the creator information" do
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      assert_equal(CurrentUser.user.id, ta.creator_id)
    end

    should "convert a tag to its normalized version" do
      tag1 = FactoryGirl.create(:tag, :name => "aaa")
      tag2 = FactoryGirl.create(:tag, :name => "bbb")
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      normalized_tags = TagAlias.to_aliased(["aaa", "ccc"])
      assert_equal(["bbb", "ccc"], normalized_tags.sort)
    end

    should "update the cache" do
      tag1 = FactoryGirl.create(:tag, :name => "aaa")
      tag2 = FactoryGirl.create(:tag, :name => "bbb")
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      assert_nil(Cache.get("ta:aaa"))
      TagAlias.to_aliased(["aaa"])
      assert_equal("bbb", Cache.get("ta:aaa"))
      ta.destroy
      assert_nil(Cache.get("ta:aaa"))
    end

    should "move saved searches" do
      tag1 = FactoryGirl.create(:tag, :name => "...")
      tag2 = FactoryGirl.create(:tag, :name => "bbb")
      ss = FactoryGirl.create(:saved_search, :tag_query => "123 ... 456", :user => CurrentUser.user)
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "...", :consequent_name => "bbb")
      ss.reload
      assert_equal("123 bbb 456", ss.tag_query)
    end

    should "update any affected posts when saved" do
      assert_equal(0, TagAlias.count)
      post1 = FactoryGirl.create(:post, :tag_string => "aaa bbb")
      post2 = FactoryGirl.create(:post, :tag_string => "ccc ddd")
      assert_equal("aaa bbb", post1.tag_string)
      assert_equal("ccc ddd", post2.tag_string)
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "ccc")
      post1.reload
      post2.reload
      assert_equal("bbb ccc", post1.tag_string)
      assert_equal("ccc ddd", post2.tag_string)
    end

    should "not validate for transitive relations" do
      ta1 = FactoryGirl.create(:tag_alias, :antecedent_name => "bbb", :consequent_name => "ccc")
      assert_difference("TagAlias.count", 0) do
        ta2 = FactoryGirl.build(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
        ta2.save
        assert(ta2.errors.any?, "Tag alias should be invalid")
        assert_equal("A tag alias for bbb already exists", ta2.errors.full_messages.join)
      end
    end

    should "move existing aliases" do
      ta1 = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      ta2 = FactoryGirl.create(:tag_alias, :antecedent_name => "bbb", :consequent_name => "ccc")
      ta1.reload
      assert_equal("ccc", ta1.consequent_name)
    end

    should "move existing implications" do
      ti = FactoryGirl.create(:tag_implication, :antecedent_name => "aaa", :consequent_name => "bbb")
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "bbb", :consequent_name => "ccc")
      ti.reload
      assert_equal("ccc", ti.consequent_name)
    end

    should "not push the antecedent's category to the consequent if the antecedent is general" do
      tag1 = FactoryGirl.create(:tag, :name => "aaa")
      tag2 = FactoryGirl.create(:tag, :name => "bbb", :category => 1)
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      tag2.reload
      assert_equal(1, tag2.category)
    end

    should "push the antecedent's category to the consequent" do
      tag1 = FactoryGirl.create(:tag, :name => "aaa", :category => 1)
      tag2 = FactoryGirl.create(:tag, :name => "bbb")
      ta = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb")
      tag2.reload
      assert_equal(1, tag2.category)
    end

    context "with an associated forum topic" do
      setup do
        @admin = FactoryGirl.create(:admin_user)
        @topic = FactoryGirl.create(:forum_topic)
        @alias = FactoryGirl.create(:tag_alias, :antecedent_name => "aaa", :consequent_name => "bbb", :forum_topic => @topic, :status => "pending")
      end

      context "and conflicting wiki pages" do
        setup do
          @wiki1 = FactoryGirl.create(:wiki_page, :title => "aaa")
          @wiki2 = FactoryGirl.create(:wiki_page, :title => "bbb")
          @alias.approve!(@admin)
          @admin.reload # reload to get the forum post the approval created.
        end

        should "update the forum topic when approved" do
          assert(@topic.posts.last, @admin.forum_posts.last)
          assert_match(/The tag alias .* been approved/, @admin.forum_posts.last.body)
        end

        should "warn about conflicting wiki pages when approved" do
          assert_match(/has conflicting wiki pages/, @admin.forum_posts.last.body)
        end
      end

      should "update the topic when processed" do
        assert_difference("ForumPost.count") do
          @alias.approve!(@admin)
        end
      end

      should "update the topic when rejected" do
        assert_difference("ForumPost.count") do
          @alias.reject!
        end
      end

      should "update the topic when failed" do
        @alias.stubs(:sleep).returns(true)
        @alias.stubs(:update_posts).raises(Exception, "oh no")
        @alias.approve!(@admin)

        assert_match(/error: oh no/, @alias.status)
        assert_match(/The tag alias .* failed during processing/, @admin.forum_posts.last.body)
      end
    end
  end
end
