# == Schema Information
#
# Table name: items
#
#  id                           :integer          not null, primary key
#  active                       :boolean          default(TRUE)
#  additional_info              :text
#  barcode_count                :integer
#  category                     :string
#  distribution_quantity        :integer
#  name                         :string
#  on_hand_minimum_quantity     :integer          default(0), not null
#  on_hand_recommended_quantity :integer
#  package_size                 :integer
#  partner_key                  :string
#  reporting_category           :string
#  value_in_cents               :integer          default(0)
#  visible_to_partners          :boolean          default(TRUE), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  item_category_id             :integer
#  kit_id                       :integer
#  organization_id              :integer
#

RSpec.describe Item, type: :model do
  let(:organization) { create(:organization) }

  describe 'Associations >' do
    it { should belong_to(:item_category).optional }
  end
  context "Validations >" do
    it "requires a unique name" do
      item = create(:item)
      expect(build(:item, name: nil)).not_to be_valid
      expect(build(:item, name: item.name)).not_to be_valid
    end

    it { should validate_presence_of(:name) }
    it { should belong_to(:organization) }
    it { should validate_numericality_of(:distribution_quantity).is_greater_than(0) }
    it { should validate_numericality_of(:on_hand_minimum_quantity).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:on_hand_recommended_quantity).is_greater_than_or_equal_to(0) }
    it { should validate_length_of(:additional_info).is_at_most(500) }
    it { should validate_numericality_of(:package_size).is_greater_than_or_equal_to(0) }
  end

  context "Filtering >" do
    it "can filter" do
      expect(subject.class).to respond_to :class_filter
    end

    specify "->by_size returns all items with the same size, per their BaseItem parent" do
      size4 = create(:base_item, size: "4", name: "Size 4 Diaper")
      size_z = create(:base_item, size: "Z", name: "Size Z Diaper")

      create(:item, base_item: size4, organization: organization)
      create(:item, base_item: size4, organization: organization)
      create(:item, base_item: size_z, organization: organization)
      expect(Item.by_size("4").length).to eq(2)
    end

    specify "->housing_a_kit returns all items which belongs_to (house) a kit" do
      name = "test kit"
      kit_params = attributes_for(:kit, name: name)
      kit_params[:line_items_attributes] = [{item_id: create(:item).id, quantity: 1}] # shouldn't be counted
      KitCreateService.new(organization_id: organization.id, kit_params: kit_params).call

      create(:item) # shouldn't be counted
      expect(Item.housing_a_kit.count).to eq(1)
      expect(Item.housing_a_kit.first.name = name)
    end

    specify "->loose returns all items which do not belongs_to a kit" do
      name = "A"
      item = create(:item, name: name, organization: organization)

      kit_params = attributes_for(:kit)
      kit_params[:line_items_attributes] = [{item_id: item.id, quantity: 1}]
      KitCreateService.new(organization_id: organization.id, kit_params: kit_params).call # shouldn't be counted

      expect(Item.loose.count).to eq(1)
      expect(Item.loose.first.name = name)
    end

    specify "->alphabetized retrieves items in alphabetical order" do
      item_c = create(:item, name: "C")
      item_b = create(:item, name: "B")
      item_a = create(:item, name: "A")

      alphabetized_list = [item_a.name, item_b.name, item_c.name]
      expect(Item.alphabetized.count).to eq(3)
      expect(Item.alphabetized.map(&:name)).to eq(alphabetized_list)
    end

    specify "->active shows items that are still active" do
      inactive_item = create(:line_item, :purchase).item
      item = create(:item)
      inactive_item.deactivate!

      expect(Item.active.to_a).to include(item)
      expect(Item.active.to_a).to_not include(inactive_item)
    end

    describe "->by_base_item" do
      it "shows the items for a particular base_item" do
        c1 = create(:base_item)
        create(:item, base_item: c1, organization: organization)
        create(:item, base_item: create(:base_item), organization: organization)

        expect(Item.by_base_item(c1).size).to eq(1)
      end

      it "can be chained to organization to constrain it to just 1 org's items" do
        c1 = create(:base_item)
        create(:item, base_item: c1, organization: organization)
        create(:item, base_item: create(:base_item), organization: organization)
        create(:item, base_item: c1, organization: create(:organization))

        expect(organization.items.by_base_item(c1).size).to eq(1)
      end
    end

    describe "->by_partner_key" do
      it "filters by partner key" do
        c1 = create(:base_item, partner_key: "foo")
        c2 = create(:base_item, partner_key: "bar")

        expect do
          create(:item, base_item: c1, partner_key: "foo", organization: organization)
          create(:item, base_item: c2, partner_key: "bar", organization: organization)
        end.to change { Item.active.size }.by(2)

        expect(Item.by_partner_key("foo").size).to eq(1)
      end
    end

    describe "->disposable" do
      it "returns records associated with disposable diapers" do
        base_1 = create(:base_item, category: "Diapers - Childrens")
        adult_base = create(:base_item, category: "Diapers - Adult")
        cloth_base = create(:base_item, category: "Diapers - Cloth (Adult)")

        disposable_1 = create(:item, :active, name: "Disposable Diaper 1", base_item: base_1, organization: organization)
        adult_1 = create(:item, :active, name: "Adult Diaper 1", base_item: adult_base, organization: organization)
        cloth_1 = create(:item, :active, name: "Cloth Diaper", base_item: cloth_base, organization: organization)

        disposables = Item.disposable

        expect(disposables.count).to eq(1)
        expect(disposables).to include(disposable_1)
        expect(disposables).to_not include(adult_1, cloth_1)
      end
    end

    describe "->cloth_diapers" do
      it "returns records associated with cloth diapers" do
        disposable_base = create(:base_item, category: "Diapers - Childrens")
        adult_cloth_base = create(:base_item, category: "Diapers - Cloth (Adult)")
        cloth_base = create(:base_item, category: "Diapers - Cloth (Kids)")

        cloth_item = create(:item, :active, name: "Cloth Diaper", base_item: cloth_base, organization: organization)
        adult_cloth_item = create(:item, :active, name: "Adult_Cloth Diaper 1", base_item: adult_cloth_base, organization: organization)
        disposable_item = create(:item, :active, name: "Disposable Diaper 1", base_item: disposable_base, organization: organization)

        cloth_diapers = Item.cloth_diapers

        expect(cloth_diapers.count).to eq(1)
        expect(cloth_diapers).to include(cloth_item)
        expect(cloth_diapers).to_not include(disposable_item, adult_cloth_item)
      end
    end

    describe "->adult_incontinence" do
      it "returns records associated with adult incontinence" do
        child_base = create(:base_item, category: "Diapers - Childrens")
        adult_cloth_base = create(:base_item, category: "Diapers - Cloth (Adult)")
        child_cloth_base = create(:base_item, category: "Diapers - Cloth (Kids)")
        adult_brief_base = create(:base_item, category: "Diapers - Adult")
        pad_base = create(:base_item, category: "Incontinence Pads - Adult", partner_key: "underpads")
        adult_incontinence_base = create(:base_item, category: "Incontinence Pads - Adult", partner_key: "adult_incontinence")
        liner_base_1 = create(:base_item, category: "Menstrual Supplies/Items", partner_key: "liners")
        liner_base_2 = create(:base_item, category: "Incontinence Pads - Adult", partner_key: "ai_liners")
        wipes_base = create(:base_item, category: "Wipes - Adults", partner_key: "adult_wipes")

        child_disposable_item = create(:item, :active, name: "Item 1", base_item: child_base, organization: organization)
        adult_cloth_item = create(:item, :active, name: "Item 2", base_item: adult_cloth_base, organization: organization)
        child_cloth_item = create(:item, :active, name: "Item 3", base_item: child_cloth_base, organization: organization)
        adult_brief_item = create(:item, :active, name: "Item 4", base_item: adult_brief_base, organization: organization)
        adult_incontinence_item = create(:item, :active, name: "Item 5", base_item: adult_incontinence_base, organization: organization)
        pad_item = create(:item, :active, name: "Item 6", base_item: pad_base, organization: organization)
        liner_item_1 = create(:item, :active, name: "Item 7", base_item: liner_base_1, organization: organization)
        liner_item_2 = create(:item, :active, name: "Item 8", base_item: liner_base_2, organization: organization)
        wipes_item = create(:item, :active, name: "Item 9", base_item: wipes_base, organization: organization)

        ai_items = Item.adult_incontinence

        expect(ai_items.count).to eq(5)
        expect(ai_items).to include(adult_cloth_item, adult_brief_item, adult_incontinence_item, pad_item, liner_item_2)
        expect(ai_items).to_not include(child_disposable_item, child_cloth_item, wipes_item, liner_item_1)
      end
    end
  end

  describe "->period_supplies" do
    it "returns records associated with period supplies" do
      liner_base_1 = create(:base_item, category: "Menstrual Supplies/Items", partner_key: "liners")
      liner_base_2 = create(:base_item, category: "Incontinence Pads - Adult", partner_key: "ai_liners")
      ai_pad_base = create(:base_item, category: "Incontinence Pads - Adult", partner_key: "underpads")
      period_pad_base = create(:base_item, category: "Menstrual Supplies/Items", partner_key: "pads")
      tampon_base = create(:base_item, category: "Menstrual Supplies/Items", partner_key: "tampons")

      liner_item_1 = create(:item, :active, name: "Item 1", base_item: liner_base_1, organization: organization)
      liner_item_2 = create(:item, :active, name: "Item 2", base_item: liner_base_2, organization: organization)
      ai_pad_item = create(:item, :active, name: "Item 3", base_item: ai_pad_base, organization: organization)
      period_pad_item = create(:item, :active, name: "Item 4", base_item: period_pad_base, organization: organization)
      tampon_item = create(:item, :active, name: "Item 5", base_item: tampon_base, organization: organization)

      period_items = Item.period_supplies

      expect(period_items.count).to eq(3)
      expect(period_items).to include(liner_item_1, period_pad_item, tampon_item)
      expect(period_items).to_not include(liner_item_2, ai_pad_item)
    end
  end

  context "Methods >" do
    describe '#can_deactivate_or_delete?' do
      let(:item) { create(:item, organization: organization) }
      let(:storage_location) { create(:storage_location, organization: organization) }

      context "with no inventory" do
        it "should return true" do
          expect(item.can_deactivate_or_delete?).to eq(true)
        end
      end

      context "in a kit" do
        before do
          create_kit(organization: organization, line_items_attributes: [
            {item_id: item.id, quantity: 1}
          ])
        end

        it "should return false" do
          expect(item.can_deactivate_or_delete?).to eq(false)
        end
      end

      context "with inventory" do
        before do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item.id => 5
            }
          })
        end
        it "should return false" do
          expect(item.can_deactivate_or_delete?).to eq(false)
        end
      end
    end

    describe '#can_delete?' do
      let(:item) { create(:item, organization: organization) }
      let(:storage_location) { create(:storage_location, organization: organization) }

      context "with no inventory" do
        it "should return true" do
          expect(item.can_delete?).to eq(true)
        end
      end

      context "in a kit" do
        before do
          create_kit(organization: organization, line_items_attributes: [
            {item_id: item.id, quantity: 1}
          ])
        end

        it "should return false" do
          expect(item.can_delete?).to eq(false)
        end
      end

      context "with inventory" do
        before do
          TestInventory.create_inventory(organization, {
            storage_location.id => {
              item.id => 5
            }
          })
        end
        it "should return false" do
          expect(item.can_delete?).to eq(false)
        end
      end

      context "with line items" do
        before do
          create(:donation, :with_items, item: item, storage_location: storage_location)
        end
        it "should return false" do
          expect(item.can_delete?).to eq(false)
        end
      end

      context "with barcode items" do
        before do
          item.barcode_count = 10
        end
        it "should return false" do
          expect(item.can_delete?).to eq(false)
        end
      end

      context "in a request" do
        before do
          create(:request, request_items: [{"item_id" => item.id, "quantity" => 5}])
        end

        it "should return false" do
          expect(item.can_delete?).to eq(false)
        end
      end
    end

    describe '#deactivate!' do
      let(:item) { create(:item) }
      context "when it can deactivate" do
        it "should succeed" do
          allow(item).to receive(:can_deactivate_or_delete?).and_return(true)
          expect { item.deactivate! }.to change { item.active }.from(true).to(false)
        end

        it 'deactivates the kit if it exists' do
          kit = create(:kit)
          item = create(:item, kit: kit)
          expect(kit).to be_active
          item.deactivate!
          expect(item).not_to be_active
          expect(kit).not_to be_active
        end
      end

      context "when it cannot deactivate" do
        it "should not succeed" do
          allow(item).to receive(:can_deactivate_or_delete?).and_return(false)
          expect { item.deactivate! }
            .to raise_error("Cannot deactivate item - it is in a storage location or kit!")
            .and not_change { item.active }
        end
      end
    end

    describe '#destroy!' do
      let(:item) { create(:item) }
      context "when it can delete" do
        it "should succeed" do
          allow(item).to receive(:can_delete?).and_return(true)
          expect { item.destroy! }.to change { Item.count }.by(-1)
        end
      end

      context "when it cannot delete" do
        it "should not succeed" do
          allow(item).to receive(:can_delete?).and_return(false)
          expect { item.destroy! }
            .to raise_error(/Failed to destroy Item/)
            .and not_change { Item.count }
          expect(item.errors.full_messages).to eq(["Cannot delete item - it has already been used!"])
        end
      end
    end

    describe '#is_in_kit?' do
      it "is true for items that are in a kit and false otherwise" do
        item_not_in_kit = create(:item, organization: organization)
        item_in_kit = create(:item, organization: organization)

        kit_params = attributes_for(:kit)
        kit_params[:line_items_attributes] = [{item_id: item_in_kit.id, quantity: 1}]
        KitCreateService.new(organization_id: organization.id, kit_params: kit_params).call
        expect(item_in_kit.is_in_kit?).to be true
        expect(item_not_in_kit.is_in_kit?).to be false
      end
    end

    describe "other?" do
      it "is true for items that are partner_key 'other'" do
        item = create(:item, base_item: create(:base_item, name: "Base"))
        other_item = create(:item, base_item: create(:base_item, name: "Other Item", partner_key: "other"))
        expect(item).not_to be_other
        expect(other_item).to be_other
      end
    end

    describe "#reactivate!" do
      context "given an array of item ids" do
        let(:item_array) { create_list(:item, 2, :inactive).collect(&:id) }
        it "sets the active trait to true for all of them" do
          expect do
            Item.reactivate(item_array)
          end.to change { Item.active.size }.by(item_array.size)
        end
      end

      context "given a single item id" do
        let(:item_id) { create(:item).id }
        it "sets the active trait to true for that item" do
          expect do
            Item.reactivate(item_id)
          end.to change { Item.active.size }.by(1)
        end
      end
    end
  end

  describe "default_quantity" do
    it "should return 50 if column is not set" do
      expect(create(:item).default_quantity).to eq(50)
    end

    it "should return the value of distribution_quantity if it is set" do
      expect(create(:item, distribution_quantity: 75).default_quantity).to eq(75)
    end

    it "should return 0 if on_hand_minimum_quantity is not set" do
      expect(create(:item).on_hand_minimum_quantity).to eq(0)
    end

    it "should return the value of on_hand_minimum_quantity if it is set" do
      expect(create(:item, on_hand_minimum_quantity: 42).on_hand_minimum_quantity).to eq(42)
    end
  end

  describe "distribution_quantity and package size" do
    it "have nil values if an empty string is passed" do
      expect(create(:item, distribution_quantity: '').distribution_quantity).to be_nil
      expect(create(:item, package_size: '').package_size).to be_nil
    end
  end

  describe "after update" do
    let(:item) { create(:item, name: "my item", kit: kit) }

    context "when item has the kit" do
      let(:kit) { create(:kit, name: "my kit") }

      it "updates kit name" do
        name = "my new name"
        item.update(name: name)
        expect(kit.name).to eq name
      end
    end

    context "when item does not have kit" do
      let(:kit) { nil }

      it "does not raise any errors" do
        allow_any_instance_of(Kit).to receive(:update).and_return(true)
        expect {
          item.update(name: "my new name")
        }.not_to raise_error
      end
    end
  end

  describe "after create" do
    let(:base_item) { create(:base_item, size: "4", name: "Tampons") }
    let(:item) { create(:item, name: "Period product", base_item:) }

    it "sets the reporting category" do
      expect(item.reporting_category).to eq("tampons")
    end
  end

  describe "versioning" do
    it { is_expected.to be_versioned }
  end

  describe "kit items" do
    context "with kit and regular items" do
      let(:organization) { create(:organization) }
      let(:base_item) { create(:base_item, name: "Kit") }
      let(:kit) { create(:kit, organization: organization) }
      let(:kit_item) { create(:item, kit: kit, organization: organization, base_item: base_item) }
      let(:regular_item) { create(:item, organization: organization) }

      it "has no reporting category" do
        expect(kit_item.reporting_category).to be(nil)
      end

      describe "#can_delete?" do
        it "returns false for kit items" do
          expect(kit_item.can_delete?).to be false
        end

        it "returns true for regular items" do
          expect(regular_item.can_delete?).to be true
        end
      end

      describe "#deactivate!" do
        it "deactivates both the kit item and its associated kit" do
          kit_item.deactivate!
          expect(kit_item.reload.active).to be false
          expect(kit.reload.active).to be false
        end

        it "only deactivates regular items" do
          regular_item.deactivate!
          expect(regular_item.reload.active).to be false
        end
      end

      describe "#validate_destroy" do
        it "prevents deletion of kit items" do
          expect { kit_item.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
          expect(kit_item.errors[:base]).to include("Cannot delete item - it has already been used!")
        end

        it "allows deletion of regular items" do
          expect { regular_item.destroy! }.not_to raise_error
        end
      end
    end
  end
end
