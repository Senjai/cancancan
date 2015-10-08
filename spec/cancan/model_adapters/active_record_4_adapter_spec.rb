require "spec_helper"

if defined? CanCan::ModelAdapters::ActiveRecord4Adapter
  describe CanCan::ModelAdapters::ActiveRecord4Adapter do
    context 'with sqlite3' do
      before :each do
        ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
        ActiveRecord::Migration.verbose = false
        (@ability = double).extend(CanCan::Ability)
      end

      context 'associations' do
        before :each do
          ActiveRecord::Schema.define do
            create_table(:parents) do |t|
              t.timestamps :null => false
            end

            create_table(:children) do |t|
              t.timestamps :null => false
              t.integer :parent_id
            end
          end

          class Parent < ActiveRecord::Base
            has_many :children, lambda { order(:id => :desc) }
          end

          class Child < ActiveRecord::Base
            belongs_to :parent
          end
        end

        it "respects scope on included associations" do
          @ability.can :read, [Parent, Child]

          parent = Parent.create!
          child1 = Child.create!(:parent => parent, :created_at => 1.hours.ago)
          child2 = Child.create!(:parent => parent, :created_at => 2.hours.ago)

          expect(Parent.accessible_by(@ability).order(:created_at => :asc).includes(:children).first.children).to eq [child2, child1]
        end
      end

      if ActiveRecord::VERSION::MINOR >= 1
        it "allows filters on enums" do
          ActiveRecord::Schema.define do
            create_table(:shapes) do |t|
              t.integer :color, default: 0, null: false
            end
          end

          class Shape < ActiveRecord::Base
            enum color: [:red, :green, :blue]
          end

          red = Shape.create!(color: :red)
          green = Shape.create!(color: :green)
          blue = Shape.create!(color: :blue)

          # A condition with a single value.
          @ability.can :read, Shape, color: Shape.colors[:green]

          expect(@ability.cannot? :read, red).to be true
          expect(@ability.can? :read, green).to be true
          expect(@ability.cannot? :read, blue).to be true

          accessible = Shape.accessible_by(@ability)
          expect(accessible).to contain_exactly(green)

          # A condition with multiple values.
          @ability.can :update, Shape, color: [Shape.colors[:red],
                                               Shape.colors[:blue]]

          expect(@ability.can? :update, red).to be true
          expect(@ability.cannot? :update, green).to be true
          expect(@ability.can? :update, blue).to be true

          accessible = Shape.accessible_by(@ability, :update)
          expect(accessible).to contain_exactly(red, blue)
        end
      end

      context 'conditions' do
        before :each do
          ActiveRecord::Schema.define do
            create_table(:records) do |t|
              t.timestamps :null => false
              t.references :ledger
              t.string :name
            end

            create_table(:ledgers) do |t|
              t.timestamps null: false
              t.string :title
            end
          end

          class Record < ActiveRecord::Base
            belongs_to :ledger
          end

          class Ledger < ActiveRecord::Base
            has_many :records
          end
        end

        it 'uses :not for negative conditions' do
          @ability.can :read, Record, :not => {:name => 'unreadable'}

          unreadable = Record.create! :name => 'unreadable'
          readable = Record.create! :name => 'readable'

          accessible = Record.accessible_by(@ability)
          expect(accessible).to include readable
          expect(accessible).not_to include unreadable
        end

        it "works when used with associations" do
          @ability.can :read, Ledger, records: { not: { name: "crappy_record" }, name: "better_record" }

          double_records = Ledger.create!(title: "unreadable")
          double_records.records.create!(name: "crappy_record")
          double_records.records.create!(name: "better_record")

          only_unreadable = Ledger.create!(title: "unreadable")
          only_unreadable.records.create!(name: "crappy_record")

          only_readable = Ledger.create!(title: "readable")
          only_readable.records.create!(name: "better_record")

          accessible = Ledger.accessible_by(@ability)
          expect(accessible).to_not include(double_records)
          expect(accessible).to_not include(only_unreadable)
          expect(accessible).to include(only_readable)
        end

        it "works when used with associations" do
          @ability.can :read, Ledger, not: { records: { name: "crappy_record" } }, records: { name: "better_record" }

          double_records = Ledger.create!(title: "unreadable")
          double_records.records.create!(name: "crappy_record")
          double_records.records.create!(name: "better_record")

          only_unreadable = Ledger.create!(title: "unreadable")
          only_unreadable.records.create!(name: "crappy_record")

          only_readable = Ledger.create!(title: "readable")
          only_readable.records.create!(name: "better_record")

          accessible = Ledger.accessible_by(@ability)
          expect(accessible).to_not include(double_records)
          expect(accessible).to_not include(only_unreadable)
          expect(accessible).to include(only_readable)
        end
      end
    end

    if Gem::Specification.find_all_by_name('pg').any?
      context 'with postgresql' do
        before :each do
          ActiveRecord::Base.establish_connection(:adapter => "postgresql", :database => "postgres", :schema_search_path => 'public')
          ActiveRecord::Base.connection.drop_database('cancan_postgresql_spec')
          ActiveRecord::Base.connection.create_database 'cancan_postgresql_spec', 'encoding' => 'utf-8', 'adapter' => 'postgresql'
          ActiveRecord::Base.establish_connection(:adapter => "postgresql", :database => "cancan_postgresql_spec")
          ActiveRecord::Migration.verbose = false
          ActiveRecord::Schema.define do
            create_table(:parents) do |t|
              t.timestamps :null => false
            end

            create_table(:children) do |t|
              t.timestamps :null => false
              t.integer :parent_id
            end
          end

          class Parent < ActiveRecord::Base
            has_many :children, lambda { order(:id => :desc) }
          end

          class Child < ActiveRecord::Base
            belongs_to :parent
          end

          (@ability = double).extend(CanCan::Ability)
        end

        it "allows overlapping conditions in SQL and merge with hash conditions" do
          @ability.can :read, Parent, :children => {:parent_id => 1}
          @ability.can :read, Parent, :children => {:parent_id => 1}

          parent = Parent.create!
          child1 = Child.create!(:parent => parent, :created_at => 1.hours.ago)
          child2 = Child.create!(:parent => parent, :created_at => 2.hours.ago)

          expect(Parent.accessible_by(@ability)).to eq([parent])
        end
      end
    end
  end
end
