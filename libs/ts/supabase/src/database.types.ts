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
          cycles: number
          egg_kind: string
          egg_received_at: string | null
          exp: number
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
          cycles?: number
          egg_kind: string
          egg_received_at?: string | null
          exp?: number
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
          cycles?: number
          egg_kind?: string
          egg_received_at?: string | null
          exp?: number
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
          rarity: string
          species_id: number
        }
        Insert: {
          egg_kind: string
          rarity: string
          species_id: number
        }
        Update: {
          egg_kind?: string
          rarity?: string
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
            foreignKeyName: 'coder_egg_species_rarity_fkey'
            columns: ['rarity']
            isOneToOne: false
            referencedRelation: 'coder_egg_rarities'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'coder_egg_species_species_id_fkey'
            columns: ['species_id']
            isOneToOne: false
            referencedRelation: 'pokedex_species'
            referencedColumns: ['id']
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
          claim_limit_tokens: number
          id: boolean
          shiny_odds: number
          tokens_per_cycle: number
          unowned_line_weight: number
        }
        Insert: {
          claim_limit_tokens: number
          id?: boolean
          shiny_odds: number
          tokens_per_cycle: number
          unowned_line_weight: number
        }
        Update: {
          claim_limit_tokens?: number
          id?: boolean
          shiny_odds?: number
          tokens_per_cycle?: number
          unowned_line_weight?: number
        }
        Relationships: []
      }
      coder_trainers: {
        Row: {
          created_at: string
          main_companion_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          main_companion_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          main_companion_id?: string
          user_id?: string
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
          id: string
          item: string | null
          level: number | null
          trigger: string
        }
        Insert: {
          id: string
          item?: string | null
          level?: number | null
          trigger: string
        }
        Update: {
          id?: string
          item?: string | null
          level?: number | null
          trigger?: string
        }
        Relationships: [
          {
            foreignKeyName: 'pokedex_evolution_methods_item_fkey'
            columns: ['item']
            isOneToOne: false
            referencedRelation: 'pokedex_items'
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
      pokedex_species: {
        Row: {
          attack: number
          capture_rate: number
          category: string | null
          defense: number
          en_genus: string | null
          en_name: string | null
          evolution_method: string | null
          evolves_from_id: number | null
          gender_rate: number
          generation: number
          growth_rate: string
          hatch_counter: number
          height: number
          hp: number
          id: number
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
          en_genus?: string | null
          en_name?: string | null
          evolution_method?: string | null
          evolves_from_id?: number | null
          gender_rate: number
          generation: number
          growth_rate: string
          hatch_counter: number
          height: number
          hp: number
          id: number
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
          en_genus?: string | null
          en_name?: string | null
          evolution_method?: string | null
          evolves_from_id?: number | null
          gender_rate?: number
          generation?: number
          growth_rate?: string
          hatch_counter?: number
          height?: number
          hp?: number
          id?: number
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
      approve_enrollment: { Args: { code: string }; Returns: Json }
      box: { Args: never; Returns: Json }
      claim: { Args: { companion_id: string }; Returns: Json }
      claim_enrollment: {
        Args: { api_key_hash: string; claim_hash: string }
        Returns: Json
      }
      eligible_ribbons: {
        Args: {
          pokemon: Database['public']['Tables']['coder_companions']['Row']
        }
        Returns: string[]
      }
      evolve: { Args: { companion_id: string }; Returns: Json }
      hatch: { Args: { companion_id: string }; Returns: Json }
      ingest: { Args: { api_key_hash: string; rollups: Json }; Returns: Json }
      level_only_methods: { Args: never; Returns: string[] }
      level_up_evolution: {
        Args: { from_id: number }
        Returns: {
          id: number
          min_level: number
        }[]
      }
      lock_companion: {
        Args: { companion_id: string; owner: string }
        Returns: {
          created_at: string
          cycles: number
          egg_kind: string
          egg_received_at: string | null
          exp: number
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
      normalize_code: { Args: { typed: string }; Returns: string }
      pending_enrollment: { Args: { code: string }; Returns: Json }
      pokedex_first_form: { Args: { species_id: number }; Returns: number }
      receive_egg: { Args: { companion_id: string }; Returns: Json }
      receive_ribbon: {
        Args: { companion_id: string; ribbon_id: string }
        Returns: Json
      }
      roll_egg: { Args: { egg_kind: string; owner: string }; Returns: string }
      set_main: { Args: { companion_id: string }; Returns: Json }
      set_markings: {
        Args: { companion_id: string; markings: number }
        Returns: Json
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
