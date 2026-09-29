export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      coder_bag: {
        Row: {
          item_id: string
          quantity: number
          user_id: string
        }
        Insert: {
          item_id: string
          quantity: number
          user_id: string
        }
        Update: {
          item_id?: string
          quantity?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_bag_item_id_fkey'
            columns: ['item_id']
            isOneToOne: false
            referencedRelation: 'pokedex_items'
            referencedColumns: ['id']
          },
        ]
      }
      coder_companion_ribbons: {
        Row: {
          companion_id: string
          received_at: string
          ribbon_id: string
        }
        Insert: {
          companion_id: string
          received_at?: string
          ribbon_id: string
        }
        Update: {
          companion_id?: string
          received_at?: string
          ribbon_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_companion_ribbons_companion_id_fkey'
            columns: ['companion_id']
            isOneToOne: false
            referencedRelation: 'coder_companions'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_companion_ribbons_ribbon_id_fkey'
            columns: ['ribbon_id']
            isOneToOne: false
            referencedRelation: 'coder_ribbons'
            referencedColumns: ['id']
          },
        ]
      }
      coder_companions: {
        Row: {
          created_at: string
          egg_kind: string
          egg_received_at: string | null
          egg_tokens: number
          exp: number
          gender: string | null
          hatched_at: string | null
          id: string
          invested_tokens: number
          is_shiny: boolean
          level: number | null
          markings: number
          species_id: number
          user_id: string
        }
        Insert: {
          created_at?: string
          egg_kind: string
          egg_received_at?: string | null
          egg_tokens?: number
          exp?: number
          gender?: string | null
          hatched_at?: string | null
          id?: string
          invested_tokens?: number
          is_shiny: boolean
          level?: number | null
          markings?: number
          species_id: number
          user_id: string
        }
        Update: {
          created_at?: string
          egg_kind?: string
          egg_received_at?: string | null
          egg_tokens?: number
          exp?: number
          gender?: string | null
          hatched_at?: string | null
          id?: string
          invested_tokens?: number
          is_shiny?: boolean
          level?: number | null
          markings?: number
          species_id?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_companions_egg_kind_fkey'
            columns: ['egg_kind']
            isOneToOne: false
            referencedRelation: 'coder_egg_kinds'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_companions_species_id_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
        ]
      }
      coder_dex_entries: {
        Row: {
          caught_at: string
          shiny_caught_at: string | null
          species_id: number
          user_id: string
        }
        Insert: {
          caught_at?: string
          shiny_caught_at?: string | null
          species_id: number
          user_id: string
        }
        Update: {
          caught_at?: string
          shiny_caught_at?: string | null
          species_id?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_dex_entries_species_id_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
        ]
      }
      coder_egg_forms: {
        Row: {
          species_id: number
        }
        Insert: {
          species_id: number
        }
        Update: {
          species_id?: number
        }
        Relationships: [
          {
            foreignKeyName: 'coder_egg_forms_species_id_fkey'
            columns: ['species_id']
            isOneToOne: true
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
        ]
      }
      coder_egg_kinds: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      coder_egg_rarities: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
          weight: number
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
          weight: number
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
          weight?: number
        }
        Relationships: []
      }
      coder_egg_species: {
        Row: {
          egg_kind: string
          species_id: number
        }
        Insert: {
          egg_kind: string
          species_id: number
        }
        Update: {
          egg_kind?: string
          species_id?: number
        }
        Relationships: [
          {
            foreignKeyName: 'coder_egg_species_egg_kind_fkey'
            columns: ['egg_kind']
            isOneToOne: false
            referencedRelation: 'coder_egg_kinds'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_egg_species_species_id_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_egg_species_species_id_rarity_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'coder_species_rarities'
            referencedColumns: ['species_id']
          },
        ]
      }
      coder_experience_levels: {
        Row: {
          growth_rate: string
          level: number
          tokens: number
        }
        Insert: {
          growth_rate: string
          level: number
          tokens: number
        }
        Update: {
          growth_rate?: string
          level?: number
          tokens?: number
        }
        Relationships: [
          {
            foreignKeyName: 'coder_experience_levels_growth_rate_fkey'
            columns: ['growth_rate']
            isOneToOne: false
            referencedRelation: 'pokedex_growth_rates'
            referencedColumns: ['id']
          },
        ]
      }
      coder_main_periods: {
        Row: {
          companion_id: string
          ended_at: string | null
          id: number
          started_at: string
          user_id: string
        }
        Insert: {
          companion_id: string
          ended_at?: string | null
          id?: never
          started_at?: string
          user_id: string
        }
        Update: {
          companion_id?: string
          ended_at?: string | null
          id?: never
          started_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_main_periods_companion_id_user_id_fkey'
            columns: ['companion_id', 'user_id']
            isOneToOne: false
            referencedRelation: 'coder_companions'
            referencedColumns: ['id', 'user_id']
          },
        ]
      }
      coder_point_entries: {
        Row: {
          created_at: string
          id: number
          points: number
          reason: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: never
          points: number
          reason: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: never
          points?: number
          reason?: string
          user_id?: string
        }
        Relationships: []
      }
      coder_request_tasks: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
          type: string
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
          type: string
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_request_tasks_type_fkey'
            columns: ['type']
            isOneToOne: false
            referencedRelation: 'pokedex_types'
            referencedColumns: ['id']
          },
        ]
      }
      coder_ribbons: {
        Row: {
          en_description: string | null
          en_name: string | null
          id: string
          ko_description: string | null
          ko_name: string | null
        }
        Insert: {
          en_description?: string | null
          en_name?: string | null
          id: string
          ko_description?: string | null
          ko_name?: string | null
        }
        Update: {
          en_description?: string | null
          en_name?: string | null
          id?: string
          ko_description?: string | null
          ko_name?: string | null
        }
        Relationships: []
      }
      coder_settings: {
        Row: {
          bonus_every_hours: number
          bonus_points: number
          id: boolean
          min_work_level: number
          points_per_hour: number
          shift_hours: number
          shiny_odds: number
          tokens_per_cycle: number
          unowned_line_weight: number
          workplaces: number
        }
        Insert: {
          bonus_every_hours: number
          bonus_points: number
          id?: boolean
          min_work_level: number
          points_per_hour: number
          shift_hours: number
          shiny_odds: number
          tokens_per_cycle: number
          unowned_line_weight: number
          workplaces: number
        }
        Update: {
          bonus_every_hours?: number
          bonus_points?: number
          id?: boolean
          min_work_level?: number
          points_per_hour?: number
          shift_hours?: number
          shiny_odds?: number
          tokens_per_cycle?: number
          unowned_line_weight?: number
          workplaces?: number
        }
        Relationships: []
      }
      coder_shop_items: {
        Row: {
          egg_kind: string | null
          id: string
          item_id: string | null
          position: number
          price: number
        }
        Insert: {
          egg_kind?: string | null
          id: string
          item_id?: string | null
          position: number
          price: number
        }
        Update: {
          egg_kind?: string | null
          id?: string
          item_id?: string | null
          position?: number
          price?: number
        }
        Relationships: [
          {
            foreignKeyName: 'coder_shop_items_egg_kind_fkey'
            columns: ['egg_kind']
            isOneToOne: false
            referencedRelation: 'coder_egg_kinds'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_shop_items_item_id_fkey'
            columns: ['item_id']
            isOneToOne: false
            referencedRelation: 'pokedex_items'
            referencedColumns: ['id']
          },
        ]
      }
      coder_species_rarities: {
        Row: {
          rarity: string
          species_id: number
        }
        Insert: {
          rarity: string
          species_id: number
        }
        Update: {
          rarity?: string
          species_id?: number
        }
        Relationships: [
          {
            foreignKeyName: 'coder_species_rarities_rarity_fkey'
            columns: ['rarity']
            isOneToOne: false
            referencedRelation: 'coder_egg_rarities'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_species_rarities_species_id_fkey'
            columns: ['species_id']
            isOneToOne: true
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
        ]
      }
      coder_trainers: {
        Row: {
          created_at: string
          main_companion_id: string
          user_id: string
          work_hours_paid: number
          work_started_at: string
        }
        Insert: {
          created_at?: string
          main_companion_id: string
          user_id: string
          work_hours_paid?: number
          work_started_at?: string
        }
        Update: {
          created_at?: string
          main_companion_id?: string
          user_id?: string
          work_hours_paid?: number
          work_started_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_trainers_main_companion_id_user_id_fkey'
            columns: ['main_companion_id', 'user_id']
            isOneToOne: false
            referencedRelation: 'coder_companions'
            referencedColumns: ['id', 'user_id']
          },
        ]
      }
      coder_workplaces: {
        Row: {
          assigned_at: string | null
          client_id: number
          companion_id: string | null
          emptied_at: string | null
          id: string
          slot: number
          task_id: string
          user_id: string
        }
        Insert: {
          assigned_at?: string | null
          client_id: number
          companion_id?: string | null
          emptied_at?: string | null
          id?: string
          slot: number
          task_id: string
          user_id: string
        }
        Update: {
          assigned_at?: string | null
          client_id?: number
          companion_id?: string | null
          emptied_at?: string | null
          id?: string
          slot?: number
          task_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'coder_workplaces_client_id_fkey'
            columns: ['client_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_workplaces_companion_id_user_id_fkey'
            columns: ['companion_id', 'user_id']
            isOneToOne: false
            referencedRelation: 'coder_companions'
            referencedColumns: ['id', 'user_id']
          },
          {
            foreignKeyName: 'coder_workplaces_task_id_fkey'
            columns: ['task_id']
            isOneToOne: false
            referencedRelation: 'coder_request_tasks'
            referencedColumns: ['id']
          },
        ]
      }
      devices: {
        Row: {
          api_key_hash: string
          created_at: string
          id: string
          last_sync_at: string | null
          name: string
          revoked_at: string | null
          user_id: string
        }
        Insert: {
          api_key_hash: string
          created_at?: string
          id: string
          last_sync_at?: string | null
          name: string
          revoked_at?: string | null
          user_id: string
        }
        Update: {
          api_key_hash?: string
          created_at?: string
          id?: string
          last_sync_at?: string | null
          name?: string
          revoked_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      enrollments: {
        Row: {
          approved_at: string | null
          claim_hash: string
          code_hash: string
          created_at: string
          device_id: string
          device_name: string
          expires_at: string
          user_id: string | null
        }
        Insert: {
          approved_at?: string | null
          claim_hash: string
          code_hash: string
          created_at?: string
          device_id: string
          device_name: string
          expires_at: string
          user_id?: string | null
        }
        Update: {
          approved_at?: string | null
          claim_hash?: string
          code_hash?: string
          created_at?: string
          device_id?: string
          device_name?: string
          expires_at?: string
          user_id?: string | null
        }
        Relationships: []
      }
      pokedex_entries: {
        Row: {
          dex: string
          en_description: string | null
          is_default: boolean
          ko_description: string | null
          number: number
          species_id: number
        }
        Insert: {
          dex: string
          en_description?: string | null
          is_default: boolean
          ko_description?: string | null
          number: number
          species_id: number
        }
        Update: {
          dex?: string
          en_description?: string | null
          is_default?: boolean
          ko_description?: string | null
          number?: number
          species_id?: number
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_entries_dex_fkey'
            columns: ['dex']
            isOneToOne: false
            referencedRelation: 'pokedex_kinds'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_entries_species_id_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
        ]
      }
      pokedex_evolution_methods: {
        Row: {
          chance: number | null
          gender: string | null
          held_item: string | null
          id: string
          item: string | null
          known_move: string | null
          level: number | null
          location: string | null
          min_beauty: number | null
          min_happiness: number | null
          party_species_id: number | null
          relative_physical_stats: number | null
          time_of_day: string | null
          trade_species_id: number | null
          trigger: string
        }
        Insert: {
          chance?: number | null
          gender?: string | null
          held_item?: string | null
          id: string
          item?: string | null
          known_move?: string | null
          level?: number | null
          location?: string | null
          min_beauty?: number | null
          min_happiness?: number | null
          party_species_id?: number | null
          relative_physical_stats?: number | null
          time_of_day?: string | null
          trade_species_id?: number | null
          trigger: string
        }
        Update: {
          chance?: number | null
          gender?: string | null
          held_item?: string | null
          id?: string
          item?: string | null
          known_move?: string | null
          level?: number | null
          location?: string | null
          min_beauty?: number | null
          min_happiness?: number | null
          party_species_id?: number | null
          relative_physical_stats?: number | null
          time_of_day?: string | null
          trade_species_id?: number | null
          trigger?: string
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_evolution_methods_held_item_fkey'
            columns: ['held_item']
            isOneToOne: false
            referencedRelation: 'pokedex_items'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_item_fkey'
            columns: ['item']
            isOneToOne: false
            referencedRelation: 'pokedex_items'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_known_move_fkey'
            columns: ['known_move']
            isOneToOne: false
            referencedRelation: 'pokedex_moves'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_location_fkey'
            columns: ['location']
            isOneToOne: false
            referencedRelation: 'pokedex_locations'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_party_species_id_fkey'
            columns: ['party_species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_trade_species_id_fkey'
            columns: ['trade_species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_evolution_methods_trigger_fkey'
            columns: ['trigger']
            isOneToOne: false
            referencedRelation: 'pokedex_evolution_triggers'
            referencedColumns: ['id']
          },
        ]
      }
      pokedex_evolution_triggers: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      pokedex_experience_levels: {
        Row: {
          exp: number
          growth_rate: string
          level: number
        }
        Insert: {
          exp: number
          growth_rate: string
          level: number
        }
        Update: {
          exp?: number
          growth_rate?: string
          level?: number
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_experience_levels_growth_rate_fkey'
            columns: ['growth_rate']
            isOneToOne: false
            referencedRelation: 'pokedex_growth_rates'
            referencedColumns: ['id']
          },
        ]
      }
      pokedex_growth_rates: {
        Row: {
          id: string
        }
        Insert: {
          id: string
        }
        Update: {
          id?: string
        }
        Relationships: []
      }
      pokedex_items: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
          sprite: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
          sprite?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
          sprite?: string | null
        }
        Relationships: []
      }
      pokedex_kinds: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      pokedex_locations: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      pokedex_moves: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      pokedex_species: {
        Row: {
          attack: number
          capture_rate: number
          category: string | null
          defense: number
          en_form_name: string | null
          en_genus: string | null
          en_name: string | null
          evolution_method: string | null
          evolves_from_id: number | null
          form_of: number | null
          gender_rate: number
          generation: number
          growth_rate: string
          hatch_counter: number
          height: number
          hp: number
          id: number
          ko_form_name: string | null
          ko_genus: string | null
          ko_name: string | null
          slug: string
          special_attack: number
          special_defense: number
          speed: number
          sprites: Json
          type1: string
          type2: string | null
          weight: number
        }
        Insert: {
          attack: number
          capture_rate: number
          category?: string | null
          defense: number
          en_form_name?: string | null
          en_genus?: string | null
          en_name?: string | null
          evolution_method?: string | null
          evolves_from_id?: number | null
          form_of?: number | null
          gender_rate: number
          generation: number
          growth_rate: string
          hatch_counter: number
          height: number
          hp: number
          id: number
          ko_form_name?: string | null
          ko_genus?: string | null
          ko_name?: string | null
          slug: string
          special_attack: number
          special_defense: number
          speed: number
          sprites?: Json
          type1: string
          type2?: string | null
          weight: number
        }
        Update: {
          attack?: number
          capture_rate?: number
          category?: string | null
          defense?: number
          en_form_name?: string | null
          en_genus?: string | null
          en_name?: string | null
          evolution_method?: string | null
          evolves_from_id?: number | null
          form_of?: number | null
          gender_rate?: number
          generation?: number
          growth_rate?: string
          hatch_counter?: number
          height?: number
          hp?: number
          id?: number
          ko_form_name?: string | null
          ko_genus?: string | null
          ko_name?: string | null
          slug?: string
          special_attack?: number
          special_defense?: number
          speed?: number
          sprites?: Json
          type1?: string
          type2?: string | null
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_species_evolution_method_fkey'
            columns: ['evolution_method']
            isOneToOne: false
            referencedRelation: 'pokedex_evolution_methods'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_species_evolves_from_id_fkey'
            columns: ['evolves_from_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_species_form_of_fkey'
            columns: ['form_of']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_species_growth_rate_fkey'
            columns: ['growth_rate']
            isOneToOne: false
            referencedRelation: 'pokedex_growth_rates'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_species_type1_fkey'
            columns: ['type1']
            isOneToOne: false
            referencedRelation: 'pokedex_types'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_species_type2_fkey'
            columns: ['type2']
            isOneToOne: false
            referencedRelation: 'pokedex_types'
            referencedColumns: ['id']
          },
        ]
      }
      pokedex_type_efficacy: {
        Row: {
          attacking_type: string
          damage_factor: number
          defending_type: string
        }
        Insert: {
          attacking_type: string
          damage_factor: number
          defending_type: string
        }
        Update: {
          attacking_type?: string
          damage_factor?: number
          defending_type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_type_efficacy_attacking_type_fkey'
            columns: ['attacking_type']
            isOneToOne: false
            referencedRelation: 'pokedex_types'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'pokedex_type_efficacy_defending_type_fkey'
            columns: ['defending_type']
            isOneToOne: false
            referencedRelation: 'pokedex_types'
            referencedColumns: ['id']
          },
        ]
      }
      pokedex_types: {
        Row: {
          en_name: string | null
          id: string
          ko_name: string | null
        }
        Insert: {
          en_name?: string | null
          id: string
          ko_name?: string | null
        }
        Update: {
          en_name?: string | null
          id?: string
          ko_name?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          display_name: string | null
          id: string
          username: string | null
        }
        Insert: {
          display_name?: string | null
          id: string
          username?: string | null
        }
        Update: {
          display_name?: string | null
          id?: string
          username?: string | null
        }
        Relationships: []
      }
      providers: {
        Row: {
          display_name: string
          id: string
        }
        Insert: {
          display_name: string
          id: string
        }
        Update: {
          display_name?: string
          id?: string
        }
        Relationships: []
      }
      usage_rollups: {
        Row: {
          device_id: string
          hour_bucket: string
          provider: string
          tokens: number
          updated_at: string
          user_id: string
        }
        Insert: {
          device_id: string
          hour_bucket: string
          provider: string
          tokens: number
          updated_at?: string
          user_id: string
        }
        Update: {
          device_id?: string
          hour_bucket?: string
          provider?: string
          tokens?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: 'usage_rollups_device_id_user_id_fkey'
            columns: ['device_id', 'user_id']
            isOneToOne: false
            referencedRelation: 'devices'
            referencedColumns: ['id', 'user_id']
          },
          {
            foreignKeyName: 'usage_rollups_provider_fkey'
            columns: ['provider']
            isOneToOne: false
            referencedRelation: 'providers'
            referencedColumns: ['id']
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      active_hours: { Args: { owner: string; since: string }; Returns: number }
      approve_enrollment: { Args: { code: string }; Returns: Json }
      aptitude: {
        Args: { species_id: number; type1: string; type2: string }
        Returns: number
      }
      assign: {
        Args: { companion_id: string; workplace_id: string }
        Returns: Json
      }
      box: { Args: never; Returns: Json }
      buy: { Args: { shop_item_id: string }; Returns: Json }
      claim: { Args: { companion_id: string; tokens: number }; Returns: Json }
      claim_enrollment: {
        Args: { api_key_hash: string; claim_hash: string }
        Returns: Json
      }
      companion_history: { Args: { companion_id: string }; Returns: Json }
      draw_gender: { Args: { species_id: number }; Returns: string }
      eligible_ribbons: {
        Args: {
          pokemon: Database['public']['Tables']['coder_companions']['Row']
        }
        Returns: string[]
      }
      evolve: { Args: { companion_id: string }; Returns: Json }
      hatch: { Args: { companion_id: string }; Returns: Json }
      ingest: { Args: { api_key_hash: string; rollups: Json }; Returns: Json }
      item_evolutions: {
        Args: { from_id: number; gender: string }
        Returns: {
          id: number
          item: string
        }[]
      }
      level_up_evolution: {
        Args: { from_id: number; gender: string }
        Returns: {
          id: number
          min_level: number
        }[]
      }
      lock_companion: {
        Args: { companion_id: string; owner: string }
        Returns: {
          created_at: string
          egg_kind: string
          egg_received_at: string | null
          egg_tokens: number
          exp: number
          gender: string | null
          hatched_at: string | null
          id: string
          invested_tokens: number
          is_shiny: boolean
          level: number | null
          markings: number
          species_id: number
          user_id: string
        }
        SetofOptions: {
          from: '*'
          to: 'coder_companions'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      lock_trainer: {
        Args: { owner: string }
        Returns: {
          created_at: string
          main_companion_id: string
          user_id: string
          work_hours_paid: number
          work_started_at: string
        }
        SetofOptions: {
          from: '*'
          to: 'coder_trainers'
          isOneToOne: true
          isSetofReturn: false
        }
      }
      my_dex: {
        Args: never
        Returns: {
          default_id: number
          shiny: boolean
          shiny_front: string
          species_id: number
        }[]
      }
      normalize_code: { Args: { typed: string }; Returns: string }
      open_workplaces: { Args: { owner: string }; Returns: undefined }
      pending_enrollment: { Args: { code: string }; Returns: Json }
      point_balance: { Args: { owner: string }; Returns: number }
      pokedex_first_form: { Args: { species_id: number }; Returns: number }
      receive_egg: { Args: { companion_id: string }; Returns: Json }
      receive_ribbon: {
        Args: { companion_id: string; ribbon_id: string }
        Returns: Json
      }
      replace_workplace: { Args: { workplace_id: string }; Returns: undefined }
      request_arrived: {
        Args: { emptied_at: string; owner: string }
        Returns: boolean
      }
      reroll: { Args: { workplace_id: string }; Returns: Json }
      roll_client: { Args: never; Returns: number }
      roll_egg: { Args: { egg_kind: string; owner: string }; Returns: string }
      roll_task: { Args: { client_id: number }; Returns: string }
      set_main: { Args: { companion_id: string }; Returns: Json }
      set_markings: {
        Args: { companion_id: string; markings: number }
        Returns: Json
      }
      settle: { Args: { workplace_id: string }; Returns: Json }
      settle_trainer: { Args: never; Returns: Json }
      shift_pay: {
        Args: {
          level: number
          species_id: number
          type1: string
          type2: string
        }
        Returns: number
      }
      start_enrollment: {
        Args: {
          claim_hash: string
          code_hash: string
          device_id: string
          device_name: string
          lifetime: string
        }
        Returns: Json
      }
      start_game: { Args: never; Returns: Json }
      usage: { Args: { range_end: string; range_start: string }; Returns: Json }
      use_item: {
        Args: { companion_id: string; item_id: string }
        Returns: Json
      }
      work: { Args: never; Returns: Json }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
