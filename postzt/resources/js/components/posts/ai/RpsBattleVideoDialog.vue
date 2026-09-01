<script setup lang="ts">
import { useHttp, usePage } from '@inertiajs/vue3';
import { trans } from 'laravel-vue-i18n';
import { reactive, ref } from 'vue';

import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { NativeSelect } from '@/components/ui/native-select';
import { Switch } from '@/components/ui/switch';
import { battleVideo } from '@/routes/app/posts';
import { rpsBattle as saveRpsBattleDefaults } from '@/routes/app/settings';

interface RpsBattleSettings {
    rock_count: number;
    paper_count: number;
    scissors_count: number;
    theme: string;
    speed: number;
    max_duration_seconds: number;
    winner_display_style: string;
    custom_winner_text: string;
    branding_enabled: boolean;
    branding_text: string;
    sound_enabled: boolean;
}

const props = defineProps<{
    postId: string;
}>();

const open = defineModel<boolean>('open', { required: true });

const page = usePage();

const shared = (page.props.rpsBattle ?? {
    settings: {},
    themes: ['default', 'pastel', 'neon', 'dark'],
    winnerDisplayStyles: ['banner', 'center', 'neon_rainbow'],
}) as { settings: Partial<RpsBattleSettings>; themes: string[]; winnerDisplayStyles: string[] };

const settings = reactive<RpsBattleSettings>({
    rock_count: 30,
    paper_count: 30,
    scissors_count: 30,
    theme: 'default',
    speed: 1.2,
    max_duration_seconds: 15,
    winner_display_style: 'banner',
    custom_winner_text: '',
    branding_enabled: false,
    branding_text: '',
    sound_enabled: false,
    ...(shared.settings ?? {}),
});

const dispatching = ref(false);
const saving = ref(false);
const errorMessage = ref<string | undefined>(undefined);
const successMessage = ref<string | undefined>(undefined);

const httpGenerate = useHttp<{ settings: RpsBattleSettings }>({ settings: settings as RpsBattleSettings });
const httpSave = useHttp<{ settings: RpsBattleSettings }>({ settings: settings as RpsBattleSettings });

const generate = async () => {
    dispatching.value = true;
    errorMessage.value = undefined;
    successMessage.value = undefined;

    try {
        httpGenerate.settings = { ...settings };
        await httpGenerate.post(battleVideo.url({ post: props.postId }));

        if (httpGenerate.hasErrors) {
            errorMessage.value = httpGenerate.errors.settings ?? trans('posts.battle_video.errors.start_failed');
            return;
        }

        successMessage.value = trans('posts.battle_video.queued');
    } catch {
        errorMessage.value = trans('posts.battle_video.errors.start_failed');
    } finally {
        dispatching.value = false;
    }
};

const saveDefaults = async () => {
    saving.value = true;
    errorMessage.value = undefined;
    successMessage.value = undefined;

    try {
        httpSave.settings = { ...settings };
        await httpSave.put(saveRpsBattleDefaults.url());

        if (httpSave.hasErrors) {
            errorMessage.value = httpSave.errors.settings ?? trans('posts.battle_video.errors.start_failed');
            return;
        }

        successMessage.value = trans('posts.battle_video.settings_saved');
    } catch {
        errorMessage.value = trans('posts.battle_video.errors.start_failed');
    } finally {
        saving.value = false;
    }
};
</script>

<template>
    <Dialog v-model:open="open">
        <DialogContent class="sm:max-w-xl">
            <DialogHeader>
                <DialogTitle>{{ $t('posts.battle_video.title') }}</DialogTitle>
                <DialogDescription>{{ $t('posts.battle_video.description') }}</DialogDescription>
            </DialogHeader>

            <div class="grid max-h-[60vh] gap-5 overflow-y-auto py-2">
                <div class="grid grid-cols-3 gap-3">
                    <div class="grid gap-2">
                        <Label for="rps-rock">{{ $t('posts.battle_video.fields.rock_count') }}</Label>
                        <Input id="rps-rock" v-model.number="settings.rock_count" type="number" min="0" max="240" />
                    </div>
                    <div class="grid gap-2">
                        <Label for="rps-paper">{{ $t('posts.battle_video.fields.paper_count') }}</Label>
                        <Input id="rps-paper" v-model.number="settings.paper_count" type="number" min="0" max="240" />
                    </div>
                    <div class="grid gap-2">
                        <Label for="rps-scissors">{{ $t('posts.battle_video.fields.scissors_count') }}</Label>
                        <Input id="rps-scissors" v-model.number="settings.scissors_count" type="number" min="0" max="240" />
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-3">
                    <div class="grid gap-2">
                        <Label for="rps-theme">{{ $t('posts.battle_video.fields.theme') }}</Label>
                        <NativeSelect id="rps-theme" v-model="settings.theme">
                            <option v-for="theme in shared.themes" :key="theme" :value="theme">{{ theme }}</option>
                        </NativeSelect>
                    </div>
                    <div class="grid gap-2">
                        <Label for="rps-style">{{ $t('posts.battle_video.fields.winner_display_style') }}</Label>
                        <NativeSelect id="rps-style" v-model="settings.winner_display_style">
                            <option v-for="style in shared.winnerDisplayStyles" :key="style" :value="style">{{ style }}</option>
                        </NativeSelect>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-3">
                    <div class="grid gap-2">
                        <Label for="rps-speed">{{ $t('posts.battle_video.fields.speed') }}</Label>
                        <Input id="rps-speed" v-model.number="settings.speed" type="number" min="0.1" max="10" step="0.1" />
                    </div>
                    <div class="grid gap-2">
                        <Label for="rps-duration">{{ $t('posts.battle_video.fields.max_duration_seconds') }}</Label>
                        <Input id="rps-duration" v-model.number="settings.max_duration_seconds" type="number" min="1" max="300" />
                    </div>
                </div>

                <div class="grid gap-2">
                    <Label for="rps-winner-text">{{ $t('posts.battle_video.fields.custom_winner_text') }}</Label>
                    <Input id="rps-winner-text" v-model="settings.custom_winner_text" :placeholder="$t('posts.battle_video.fields.custom_winner_text')" />
                </div>

                <div class="flex items-center justify-between">
                    <Label for="rps-sound">{{ $t('posts.battle_video.fields.sound_enabled') }}</Label>
                    <Switch id="rps-sound" v-model="settings.sound_enabled" />
                </div>

                <div class="space-y-3">
                    <div class="flex items-center justify-between">
                        <Label for="rps-branding">{{ $t('posts.battle_video.fields.branding_enabled') }}</Label>
                        <Switch id="rps-branding" v-model="settings.branding_enabled" />
                    </div>
                    <div v-if="settings.branding_enabled" class="grid gap-2">
                        <Label for="rps-branding-text">{{ $t('posts.battle_video.fields.branding_text') }}</Label>
                        <Input id="rps-branding-text" v-model="settings.branding_text" placeholder="@YourHandle" />
                    </div>
                </div>

                <p v-if="errorMessage" class="text-xs font-semibold text-rose-700">{{ errorMessage }}</p>
                <p v-if="successMessage" class="text-xs font-semibold text-emerald-700">{{ successMessage }}</p>
            </div>

            <DialogFooter>
                <Button variant="outline" :loading="saving" :disabled="dispatching" @click="saveDefaults">
                    {{ $t('posts.battle_video.save_defaults') }}
                </Button>
                <Button :loading="dispatching" :disabled="saving" @click="generate">
                    {{ $t('posts.battle_video.generate') }}
                </Button>
            </DialogFooter>
        </DialogContent>
    </Dialog>
</template>
